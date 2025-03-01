#+feature dynamic-literals

package skyjo

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:math/rand"
import rl "vendor:raylib"

// ============================================================================
// Type Aliases
// ============================================================================

V2 :: rl.Vector2
Tex :: rl.Texture2D
Rec :: rl.Rectangle

// ============================================================================
// Global Constants
// ============================================================================

SCREEN_WIDTH ::  750
SCREEN_HEIGHT :: 1000
SCALE :: (SCREEN_HEIGHT / SCREEN_WIDTH) * 5
PADDING :: 2

HAND_SIZE :: 12
MAX_PLAYERS :: 4

// Pixel dimensions from spritesheet
SPRITE_CARD_X :: 1 
SPRITE_CARD_Y :: 73 
SPRITE_CARD_W :: 18
SPRITE_CARD_H :: 26

CARD_MAP := map[i8][]i8 { 
    5 = []i8 { -2 },
    10 = []i8 { -1, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 },
    15 = []i8 { 0 },
}

// ============================================================================
// Utilities
// ============================================================================

draw_circle :: proc(pos: V2, rad: f32, color: rl.Color) {
    rl.DrawCircle(
        i32(pos.x),
        i32(pos.y),
        rad,
        color
    )
}

v2_in_rec :: proc(pos: V2, rec: Rec) -> bool {
    return (pos.x > rec.x) && (pos.x < (rec.x + rec.width)) && (pos.y > rec.y) && (pos.y < (rec.y + rec.height))
}

rec_scale :: proc (rec: Rec, scale: f32) -> Rec {
    return Rec {
        x = rec.x,
        y = rec.y,
        width = rec.width * scale,
        height = rec.height* scale,
    }
}

// ============================================================================
// States
// ============================================================================

GamePhase :: enum {
    Deal,
    Select,
    End,
}

// ============================================================================
// Card Type
// ============================================================================

Card :: struct {
    val: i8,
    tex_partial: Rec,
    is_shown: bool,
}

card_init :: proc(val: i8) -> Card {
    // Determine offsets to the card textures in the spritesheet
    x_offset: f32
    if val < 0          do x_offset = (SPRITE_CARD_W + 1) * 4   // Purple Card
    else if val == 0    do x_offset = (SPRITE_CARD_W + 1) * 3   // Blue Card
    else if val < 5     do x_offset = (SPRITE_CARD_W + 1) * 2   // Green Card
    else if val < 9     do x_offset = SPRITE_CARD_W + 1         // Yellow Card
    else                do x_offset = 0                         // Red Card

    return Card {
        val = val,
        tex_partial = Rec { x = SPRITE_CARD_X + x_offset, y = SPRITE_CARD_Y, width = SPRITE_CARD_W, height = SPRITE_CARD_H },
        is_shown = true, // TODO
    }
}

card_deinit :: proc(card: ^Card) {
    // TODO: remove?
}

card_render :: proc(card: ^Card, tex: Tex, pos: V2, tint: rl.Color) {
    rec := Rec { pos.x, pos.y, card.tex_partial.width * SCALE, card.tex_partial.height * SCALE }
    rl.DrawTexturePro(
        tex,
        card.tex_partial,
        rec,
        V2 {  },
        0,
        tint
    )

    str_builder: strings.Builder
    fmt.sbprintf(&str_builder, "%d", card.val)
    rl.DrawText(strings.to_cstring(&str_builder), i32(pos.x) + i32(rec.width / 2), i32(pos.y) + i32(rec.height / 2), 30, rl.BLACK)
}

card_shuffle :: proc(deck: ^[dynamic]Card) {
    indexes := make([dynamic]int)
    for index in 0..<len(deck) do append(&indexes, index)
    for index in 0..<len(deck) {
        swap_index := index
        for index == swap_index {
            swap_index = rand.choice(indexes[:])
        }
        temp := deck[swap_index]
        deck[swap_index] = deck[index]
        deck[index] = temp
    }
}

card_move :: proc(deck_a: ^[dynamic]Card, deck_b: ^[dynamic]Card) {
    card, ok := pop_safe(deck_a)
    assert(ok, "failed to move card")
    append_elem(deck_b, card)
}

// ============================================================================
// Player Type
// ============================================================================

Player :: struct {
    name: string,
    score: i32,
    hand: [dynamic]Card,
    hand_pos: V2,
    is_playing: bool,
}

player_init :: proc(name: string, hand_pos: V2) -> Player {
    hand := make([dynamic]Card, 0, HAND_SIZE)
    return Player {
        hand = hand,
        name = name,
        hand_pos = hand_pos,
    }
}

player_deinit :: proc(player: ^Player) {
    delete(player.hand)
}

player_render_hand :: proc(player: ^Player, card_tex: Tex) {
    for &card, i in player.hand {
        x_offset: i32 = i32(i % 4)
        y_offset: i32 = i32(i / 4)
        x_scaled := card.tex_partial.width * SCALE
        y_scaled := card.tex_partial.height * SCALE

        pos := V2 {
            player.hand_pos.x + (f32(x_offset) * x_scaled) + f32(x_offset * PADDING),
            player.hand_pos.y + (f32(y_offset) * y_scaled) + f32(y_offset * PADDING),
        }

        rec := Rec { 
            pos.x, pos.y, 
            x_scaled, y_scaled,
        }

        tint: rl.Color
        if player.is_playing {
            tint = rl.WHITE if v2_in_rec(rl.GetMousePosition(), rec) else rl.LIGHTGRAY
        }
        else {
            tint = rl.DARKGRAY
        }

        card_render(&card, card_tex, pos, tint)
    }
}

// ============================================================================
// Game State Type
// ============================================================================

GameState :: struct {
    phase: GamePhase,
    card_tex: Tex,
    deck: [dynamic]Card,
    discard_pile: [dynamic]Card,
    players: [dynamic]Player,
    current_player: int,
}

init :: proc() -> GameState {
    deck := make([dynamic]Card, 0, 155)
    discard_pile := make([dynamic]Card, 0, 155)
    players := make([dynamic]Player, 0, 2)
    card_tex := rl.LoadTexture("./assets.png")

    append(&players, player_init("Player1", V2 { PADDING, SCREEN_HEIGHT - f32(3 * ((SPRITE_CARD_H * SCALE) + 1)) - PADDING }))
    append(&players, player_init("Player2", V2 { PADDING, PADDING }))

    for num_cards, vals in CARD_MAP {
        for val in vals {
            for i in 0..=num_cards {
                append(&deck, card_init(val))
            }
        }
    }
   
    return GameState {
        phase = GamePhase.Deal,
        card_tex = card_tex,
        deck = deck,
        discard_pile = discard_pile,
        players = players,
    }
}

deinit :: proc(state: ^GameState) {
    for &player in state.players {
        player_deinit(&player)
    }
    rl.UnloadTexture(state.card_tex)
}

update :: proc(state: ^GameState) {
    rl.DrawText("SKYJO", SCREEN_WIDTH/2, SCREEN_HEIGHT/2, 20 * SCALE, rl.WHITE)

    if state.phase == GamePhase.Deal {
        // Check scores
        for player in state.players {
            if player.score >= 100 {
                state.phase = GamePhase.End
                return
            }
        }

        // Put all players hands back in the deck
        for &player in state.players {
            for len(player.hand) > 0 {
                card_move(&player.hand, &state.deck)
            }
        }

        // Put all discarded cards back in the deck
        for len(state.discard_pile) > 0 {
            card_move(&state.discard_pile, &state.deck)
        }

        // Shuffle then deal new hands
        card_shuffle(&state.deck)
        for &player in state.players {
            for len(player.hand) < HAND_SIZE {
                card, ok := pop_safe(&state.deck);
                assert(ok, "failed to move card")
                append_elem(&player.hand, card)
            }
        }

        // Reset face-up state for all cards in the deck
        for &card in state.deck {
            card.is_shown = false
        }

        // Place top card face-up in discard pile
        card_move(&state.deck, &state.discard_pile)
        state.discard_pile[0].is_shown = true
    
        state.phase = GamePhase.Select
    }
    else if (state.phase == GamePhase.Select) {
        // TODO
    }

    for &player, i in state.players {
        player.is_playing = (i == state.current_player)
        player_render_hand(&player, state.card_tex)
    } 
}

main :: proc() {
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "skyjo")
    defer rl.CloseWindow()
    rl.SetWindowPosition(2600, 100)

    rl.SetTargetFPS(60)

    state := init()
    defer deinit(&state)

    for !rl.WindowShouldClose() {
        if rl.IsKeyPressed(rl.KeyboardKey.P) {
            fmt.println("Taking screenshot")
            rl.TakeScreenshot("screenshot.png")
        }

        rl.BeginDrawing()
        defer rl.EndDrawing()

        rl.ClearBackground(rl.DARKBLUE)

        update(&state)
    }
}

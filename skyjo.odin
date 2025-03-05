#+feature dynamic-literals

// ============================================================================
// TODO:
// -- Cards as sprites
// -- Turn based state handling
// -- Tagged unions as state data rather than enums?
// -- Decks to use circular buffers so cards can be pushed to the bottom
// -- Safety check for when the deck runs out of cards
// -- Fix screen scaling issues
// -- Make hand 4x3 matrix
// -- Sometimes one of the cards in a hand doesn't render??
// -- Shaders/Animations/Background/Fonts
// ============================================================================

package skyjo

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:math/rand"
import "core:math"
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
DECK_OFFSET_X :: 0.75
DECK_OFFSET_Y :: 0.75
SCORE_OFFSET_X :: 0.75
SCORE_OFFSET_Y :: 0.25

HAND_SIZE :: 12
MAX_PLAYERS :: 4

// Pixel dimensions from spritesheet
SPRITE_CARD_X :: 1 
SPRITE_CARD_Y :: 73 
SPRITE_CARD_W :: 18
SPRITE_CARD_H :: 26

// Background asset offsets
CLOUD_OFFSETS := []Rec { 
    Rec { x = 0, y = 165, width = 100, height = 165 },
} 

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

draw_instruction :: proc(text: cstring) {
    rl.DrawText(text, 0, SCREEN_HEIGHT/2, 5 * SCALE, rl.WHITE)
}

draw_int :: proc($T: typeid, val: T, x: i32, y: i32, size: i32, color: rl.Color) {
    str_builder: strings.Builder
    fmt.sbprintf(&str_builder, "%d", val)
    rl.DrawText(strings.to_cstring(&str_builder), x, y, size, color)
}

v2_in_rec :: proc(pos: V2, rec: Rec) -> bool {
    return (pos.x > rec.x) && (pos.x < (rec.x + rec.width)) && (pos.y > rec.y) && (pos.y < (rec.y + rec.height))
}

v2_operation :: proc(vec1: V2, vec2: V2, fn: proc(f32, f32) -> f32) -> V2 {
    return V2 { fn(vec1.x, vec2.x), fn(vec1.y, vec2.y) }
}

v2_operation_val :: proc(vec: V2, val: f32, fn: proc(f32, f32) -> f32) -> V2 {
    return V2 { fn(vec.x, val), fn(vec.y, val) }
}

rec_scale :: proc (rec: Rec, scale: f32) -> Rec {
    return Rec {
        x = rec.x,
        y = rec.y,
        width = rec.width * scale,
        height = rec.height* scale,
    }
}

facedown_texture :: proc() -> Rec {
    return Rec { 
        x = SPRITE_CARD_X + ((SPRITE_CARD_W + 1)*4), 
        y = SPRITE_CARD_Y - ((SPRITE_CARD_H + 1)), 
        width = SPRITE_CARD_W, 
        height = SPRITE_CARD_H 
    } 
}

// ============================================================================
// Enums
// ============================================================================

GamePhase :: enum {
    Deal,
    FlipInitialTwoCards,
    SelectFromPile,
    DeckFlipped,
    ReplaceFromHand,
    FlipFromHand,
    EndRound,
    EndGame,
}

SelectableCards :: enum {
    None,
    Faceup,
    Facedown,
    AllInHand,
    DiscardPile,
    Deck,
}

// ============================================================================
// Sprite Type
// ============================================================================

Cloud :: struct {
    tex: Tex,
    partial: Rec,
    scale: f32,
    pos: V2,
    vel: V2,
    tint: rl.Color,
}

cloud_width :: proc(cloud: Cloud) -> f32 {
    using cloud
    return partial.width * SCALE * scale
}

cloud_update :: proc(cloud: ^Cloud, dt: f32) {
    // Restart position
    if (cloud.pos.x + cloud_width(cloud^)) < 0 {
        cloud.pos.x = SCREEN_WIDTH
    }
    // Update Velocity
    cloud.pos.x += cloud.vel.x * dt
    cloud.pos.y += cloud.vel.y * dt
}

cloud_render :: proc(cloud: Cloud) {
    using cloud
    rl.DrawTexturePro(
        tex,
        partial,
        Rec { pos.x, pos.y, partial.width * SCALE * scale, partial.height * SCALE * scale },
        V2 {},
        0,
        tint
    )
}

// ============================================================================
// Card Type
// ============================================================================

Card :: struct {
    val: i8,
    tex_partial: Rec,
    is_shown: bool,
    alive: bool,
    tint: rl.Color,
    pos: V2,
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
        is_shown = true,
        alive = true,
        tint = rl.DARKGRAY,
        pos = V2 {}
    }
}

card_render :: proc(card: ^Card, tex: Tex) {
    using card
    
    if !alive {
        return
    }

    rec := Rec { pos.x, pos.y, tex_partial.width * SCALE, tex_partial.height * SCALE }
    texture_section: Rec

    rl.DrawTexturePro(
        tex,
        tex_partial if is_shown else facedown_texture(),
        rec,
        V2 {},
        0,
        tint
    )

    if card.is_shown {
        draw_int(i8, card.val, i32(card.pos.x) + i32(rec.width / 2), i32(card.pos.y) + i32(rec.height / 2), 30, rl.BLACK )
    }
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

card_swap :: proc(card_a: ^Card, card_b: ^Card) {
    temp := card_a^
    card_a^ = card_b^
    card_b^ = temp
}

card_highlighted :: proc(card: ^Card) -> bool {
    return v2_in_rec(
        rl.GetMousePosition(),
        Rec {
            card.pos.x, 
            card.pos.y, 
            card.tex_partial.width * SCALE,
            card.tex_partial.height * SCALE,
        }
    )
}

card_apply_highlight :: proc(card: ^Card, highlighted: bool, selectable: bool, time: f32) {
    using card
    if highlighted {
        if selectable && card_highlighted(card) {
            tint = rl.WHITE if card_highlighted(card) else rl.LIGHTGRAY
            fade_time: f32 = 0.25
            interpolation_factor := (1.0 + math.sin_f32((time * math.PI * 2.0) / fade_time)) / 2.0
            tint = rl.ColorLerp(rl.WHITE, rl.LIGHTGRAY, interpolation_factor)
        }
        else {
            tint = rl.LIGHTGRAY
        }
    }
    else {
        tint = rl.DARKGRAY
    }
}

// ============================================================================
// Player Type
// ============================================================================

Player :: struct {
    name: string,
    hand: [dynamic]Card,
    hand_pos: V2,
    is_playing: bool,
    score: i32,
}

player_init :: proc(name: string, hand_pos: V2) -> Player {
    hand := make([dynamic]Card, 0, HAND_SIZE)
    return Player {
        hand = hand,
        name = name,
        hand_pos = hand_pos,
        score = 0,
    }
}

player_deinit :: proc(player: ^Player) {
    delete(player.hand)
}

player_score :: proc(player: Player) -> i32 {
    score: i32 = 0
    for card in player.hand {
        if card.alive && card.is_shown {
            score += i32(card.val)
        }
    }

    return score
}

player_render_hand :: proc(player: ^Player, card_tex: Tex) {
    for &card, i in player.hand {
        x_offset: i32 = i32(i % 4)
        y_offset: i32 = i32(i / 4)
        x_scaled := card.tex_partial.width * SCALE
        y_scaled := card.tex_partial.height * SCALE

        card.pos = V2 {
            player.hand_pos.x + (f32(x_offset) * x_scaled) + f32(x_offset * PADDING),
            player.hand_pos.y + (f32(y_offset) * y_scaled) + f32(y_offset * PADDING),
        }

        card_render(&card, card_tex)
    }
}

player_select_card :: proc(player: ^Player, card: ^Card) -> bool {
    if card_highlighted(card) {
        if rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
            return true
        }
    }
    return false
}

player_select_from_cards :: proc(player: ^Player, cards: []Card) -> (bool, int) {
    for &card, i in cards {
        if player_select_card(player, &card) {
            return true, i
        }
    }
    return false, 0
}

player_select_from_faceup_hand :: proc(player: ^Player) -> (bool, int) {
    using player
    for &card, i in hand {
        if card.is_shown && player_select_card(player, &card) {
            return true, i
        }
    }
    return false, 0
}

player_select_from_facedown_hand :: proc(player: ^Player) -> (bool, int){
    using player
    for &card, i in hand {
        if !card.is_shown && player_select_card(player, &card) {
            return true, i
        }
    }
    return false, 0
}

player_num_faceup :: proc(player: Player) -> u8 {
    num: u8 = 0
    for card in player.hand {
        if card.is_shown do num += 1
    }
    return num
}

player_num_facedown :: proc(player: Player) -> u8 {
    num: u8 = 0
    for card in player.hand {
        if !card.is_shown do num += 1
    }
    return num
}

player_print_hand :: proc(player: Player) {
    using player
    fmt.print(name)
    for card in hand do fmt.print(" ", card.val)
    fmt.println()
}

// ============================================================================
// Game State Type
// ============================================================================

GameState :: struct {
    phase: GamePhase,
    card_tex: Tex,
    clouds: [dynamic]Cloud,
    deck: [dynamic]Card,
    discard: Card,
    players: [dynamic]Player,
    current_player: int,
    time: f32,
}

print_deck :: proc(state: GameState, num_cards: u8) {
    using state
    fmt.printf("deck[:%d]", num_cards)
    for card in deck[:num_cards] do fmt.print(" ", card.val)
    fmt.println()
}

print_discard :: proc(state: GameState) {
    using state
    fmt.println("discard ", discard.val)
}

render_deck :: proc(state: ^GameState) {
    next_card := &state.deck[0]
    next_card.pos = V2 { 
        (SCREEN_WIDTH * DECK_OFFSET_X) + ((next_card.tex_partial.width/2)*SCALE) + (PADDING*4), 
        (SCREEN_HEIGHT * DECK_OFFSET_Y) 
    }

    card_render(next_card, state.card_tex)

    // TODO: render a deck sprite (diagonal card pile)
}

render_discard_pile :: proc(state: ^GameState) {
    next_card := &state.discard
    next_card.is_shown = true; 
    next_card.pos = V2 { 
        (SCREEN_WIDTH * DECK_OFFSET_X) - ((next_card.tex_partial.width/2)*SCALE) - (PADDING*4), 
        (SCREEN_HEIGHT * DECK_OFFSET_Y) 
    }

    card_render(next_card, state.card_tex)

    // TODO: render a deck sprite (diagonal card pile growing from zero until a max)
}

render_selected_card :: proc(state: ^GameState) {    
    if !(state.phase == GamePhase.FlipFromHand) && !(state.phase == GamePhase.DeckFlipped) {
        return
    }

    card := &state.deck[0] if state.phase == GamePhase.DeckFlipped else &state.discard
    card_render(card, state.card_tex)
}

render_scores :: proc(state: GameState) {
    // Round scores
    draw_int(i32, player_score(state.players[0]), cast(i32)(SCREEN_WIDTH - 200), i32(math.ceil_f32(SCREEN_HEIGHT * SCORE_OFFSET_Y)), 50, rl.WHITE if state.players[0].is_playing else rl.DARKGRAY)
    draw_int(i32, player_score(state.players[1]), cast(i32)(SCREEN_WIDTH - 200), i32(math.ceil_f32(SCREEN_HEIGHT * SCORE_OFFSET_Y)) - 50, 50, rl.WHITE if state.players[1].is_playing else rl.DARKGRAY)

    // Game scores
    score1 := state.players[0].score
    score2 := state.players[1].score
    color1: rl.Color
    color2: rl.Color

    if score1 == score2 {
        color1 = rl.YELLOW
        color2 = rl.YELLOW
    }
    else if score1 > score2 {
        color1 = rl.RED
        color2 = rl.GREEN
    }
    else {
        color1 = rl.GREEN
        color2 = rl.RED
    }

    draw_int(i32, score1, cast(i32)(SCREEN_WIDTH - 100), i32(math.ceil_f32(SCREEN_HEIGHT * SCORE_OFFSET_Y)), 50, color1)
    draw_int(i32, score2, cast(i32)(SCREEN_WIDTH - 100), i32(math.ceil_f32(SCREEN_HEIGHT * SCORE_OFFSET_Y)) - 50, 50, color2)
}

next_turn :: proc(state: ^GameState) {
    using state

    index := current_player
    next := (current_player + 1) % 2
    hand := players[current_player].hand

    // Check for any 3 in a row columns
    for i in 0..=3 {
        if (hand[i].val >= 0) &&
                (hand[i].is_shown) && (hand[i + 4].is_shown) && (hand[i + 8].is_shown) &&
                (hand[i].val == hand[i + 4].val) && (hand[i].val == hand[i + 8].val) {
            hand[i].alive = false
            hand[i + 4].alive = false
            hand[i + 8].alive = false
            hand[i].is_shown = false
            hand[i + 4].is_shown = false
            hand[i + 8].is_shown = false
        } 
    }

    // If any cards are facedown then the round is not yet finished
    for card in players[current_player].hand {
        if card.alive && !card.is_shown {
            current_player = next
            phase = GamePhase.SelectFromPile
            return
        }
    }

    // Check that the player who ended the round has the least points otherwise apply penalty
    ending_player_score := player_score(players[index])
    next_player_score := player_score(players[next])
    if ending_player_score >= next_player_score do ending_player_score *= 2
    players[index].score += ending_player_score
    players[next].score += next_player_score
    phase = GamePhase.EndGame if (players[index].score >= 100) || (players[next].score >= 100) else GamePhase.EndRound
}

load_clouds :: proc() -> [dynamic]Cloud {
    clouds := make([dynamic]Cloud, 0, 100)
    tex := rl.LoadTexture("./assets/clouds.png")

    // Create parallax effect 

    num := 3
    scale: f32 = 0.5
    for i in 0..<num {
        append(&clouds, Cloud {
            tex = tex,
            partial = CLOUD_OFFSETS[0],
            scale = scale,
            pos = V2 { 
                (SCREEN_WIDTH*0.75) + ((SCREEN_WIDTH*0.75) * (f32(i) / f32(num))),
                (SCREEN_HEIGHT * 0.75) - ((SCREEN_HEIGHT*0.75) * (f32(i) / f32(num))) - (CLOUD_OFFSETS[0].height * scale) },
            vel = V2{ -50, 0 },
            tint = rl.Color { 255, 255, 255, 200 },
        })
    }

    for i in 0..<5 {
        farther_scale: f32 = 0.25
        farther_partial := CLOUD_OFFSETS[0]
        append(&clouds, Cloud {
            tex = tex,
            partial = farther_partial,
            scale = farther_scale,
            pos = V2 { SCREEN_WIDTH - (f32(i) * 500), (SCREEN_HEIGHT >> 1) + f32(i)},
            vel = V2{ -25, 0 },
            tint = rl.Color { 255, 255, 255, 128 },
        })
    }

    for i in 0..<5 {
        farther_scale: f32 = 0.125
        farther_partial := CLOUD_OFFSETS[0]
        append(&clouds, Cloud {
            tex = tex,
            partial = farther_partial,
            scale = farther_scale,
            pos = V2 { (SCREEN_WIDTH >> 1) - (f32(i) * 500), (SCREEN_HEIGHT >> 1) - (farther_partial.height * farther_scale * 5) + (f32(i) * (SCREEN_HEIGHT >> 1) / f32(i))},
            vel = V2{ -12, 0 },
            tint = rl.Color { 255, 255, 255, 64 },
        })
    }

    return clouds
}

unload_clouds :: proc(state: ^GameState) {
    using state
    rl.UnloadTexture(clouds[0].tex) // TODO: store this ID somewhere else
    delete(clouds)
}

init :: proc() -> GameState {
    deck := make([dynamic]Card, 0, 155)
    card_tex := rl.LoadTexture("./assets/cards.png")

    players := make([dynamic]Player, 0, 2)
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
        clouds = load_clouds(),
        deck = deck,
        players = players,
    }
}

deinit :: proc(state: ^GameState) {
    for &player in state.players {
        player_deinit(&player)
    }
    rl.UnloadTexture(state.card_tex)
}

deal :: proc(state: ^GameState) {
    using state

    // Check scores
    for player in players {
        if player_score(player) >= 100 {
            phase = GamePhase.EndGame
        }
    }

    // Put all players hands back in the deck
    for &player in players {
        for len(player.hand) > 0 {
            card_move(&player.hand, &deck)
        }
    }

    // Put all discarded cards back in the deck
    append(&deck, discard)

    // Reset face-up state for all cards in the deck
    for &card in deck {
        card.is_shown = false
        card.alive = true
    }

    // Shuffle then deal new hands
    card_shuffle(&deck)
    for &player in players {
        for len(player.hand) < HAND_SIZE {
            card, ok := pop_safe(&deck);
            assert(ok, "failed to move card")
            append_elem(&player.hand, card)
        }
    }

    // Place top card face-up in discard pile
    discard = pop(&deck)
    discard.is_shown = true

    phase = GamePhase.FlipInitialTwoCards
}

flip_initial_two_cards :: proc(state: ^GameState) {
    using state
    draw_instruction("choose 2 cards to flip")

    selected, index := player_select_from_facedown_hand(&players[current_player])
    if selected {
        players[current_player].hand[index].is_shown = true
    }

    num1: u8 = player_num_faceup(state.players[current_player])
    num2: u8 = player_num_faceup(state.players[(current_player + 1) % 2])
    assert(num1 < 3, "Invalid state for FlipInitialTwoCards")
    assert(num2 < 3, "Invalid state for FlipInitialTwoCards")

    if (num1 == 2) && (num2 == 2) {
        current_player = (current_player + 1) % 2
        phase = GamePhase.SelectFromPile
    }
    else if num1 == 2 {
        current_player = (current_player + 1) % 2
    }
}

select_from_pile :: proc (state: ^GameState) {
    using state
    draw_instruction("select from a pile")
    player_current := &players[current_player]
    cards: [2]Card = { discard, deck[0] }
    selected, index := player_select_from_cards(player_current, cards[:])
    if selected {
        assert(index < 2, "player selected invalid card")
        if index == 0 {
            phase = GamePhase.ReplaceFromHand
        }
        else {
            phase = GamePhase.DeckFlipped
            deck[0].is_shown = true
        }
    }
}

deck_flipped :: proc(state: ^GameState) {
    using state
    player_current := &players[current_player]
    if player_select_card(player_current, &discard) {
        discard = deck[0]
        pop_front(&deck)
        deck[0].is_shown = false
        phase = GamePhase.FlipFromHand
    }
    else {
        replace_from_hand(state)
    }
}

replace_from_hand :: proc(state: ^GameState) {
    using state
    player_current := &players[current_player]
    for &card in player_current.hand {
        if player_select_card(player_current, &card) {
            temp := card
            card = pop_front(&deck) if deck[0].is_shown else discard
            discard = temp
            card.is_shown = true
            next_turn(state)
            break
        }
    }

}

flip_from_hand :: proc(state: ^GameState) {
    using state
    player_current := &players[current_player]
    selected, index := player_select_from_facedown_hand(player_current);
    if selected {
        player_current.hand[index].is_shown = true
        next_turn(state)
    }
}

end_round :: proc(state: ^GameState) {
    using state
    for &player, index in players {
        for &card in player.hand {
            card.is_shown = true
            card.tint = rl.WHITE
        }
    }
    // TODO: use button
    draw_instruction("round ended\npress N to start next round")
    if rl.IsKeyPressed(rl.KeyboardKey.N){
        phase = GamePhase.Deal
    }
}

end_game :: proc(state: ^GameState) {
    draw_instruction("game ended")
}

highlight_selectable :: proc(state: ^GameState, selectable: SelectableCards, time: f32) {
    using state
    switch selectable {
        // TODO: this is NASTY...refactor idiot...
        case SelectableCards.Faceup:  fallthrough
        case SelectableCards.Facedown: fallthrough
        case SelectableCards.AllInHand: fallthrough
        case SelectableCards.None: {
            for &player, index in players {
                for &card in player.hand {
                    is_selectable: bool
                    #partial switch selectable {
                        case SelectableCards.Faceup: is_selectable = card.is_shown
                        case SelectableCards.Facedown: is_selectable = !card.is_shown
                        case SelectableCards.AllInHand: is_selectable = true
                        case SelectableCards.None: is_selectable = false
                    }
                    card_apply_highlight(&card, index == current_player, is_selectable, time)
                }
            }
        }
        case SelectableCards.DiscardPile: card_apply_highlight(&discard, true, true, time)
        case SelectableCards.Deck: card_apply_highlight(&deck[0], true, true, time)
    }
}

render_player_cards :: proc(state: ^GameState) {
    using state
    for &player, index in players {
        player_render_hand(&player, card_tex)
    }
}

render_clouds :: proc(state: ^GameState, dt: f32) {
    using state
    for &cloud in clouds {
        cloud_update(&cloud, dt)
        cloud_render(cloud)
    }
}

update :: proc(state: ^GameState, dt: f32) {
    using state

    time += dt

    switch state.phase {
        case GamePhase.Deal: { 
            deal(state)
        }
        case GamePhase.FlipInitialTwoCards: { 
            flip_initial_two_cards(state)
            highlight_selectable(state, SelectableCards.Facedown, time)
        }
        case GamePhase.SelectFromPile: { 
            select_from_pile(state)
            highlight_selectable(state, SelectableCards.None, time)
            highlight_selectable(state, SelectableCards.Deck, time)
            highlight_selectable(state, SelectableCards.DiscardPile, time)
        }
        case GamePhase.ReplaceFromHand: { 
            replace_from_hand(state)
            highlight_selectable(state, SelectableCards.AllInHand, time)
        }
        case GamePhase.DeckFlipped: { 
            deck_flipped(state)
            highlight_selectable(state, SelectableCards.AllInHand, time)
            highlight_selectable(state, SelectableCards.DiscardPile, time)
        }
        case GamePhase.FlipFromHand: { 
            flip_from_hand(state)
            highlight_selectable(state, SelectableCards.Facedown, time)
        }
        case GamePhase.EndRound: { 
            end_round(state)
        }
        case GamePhase.EndGame: { 
            end_game(state)
        }
    }

    render_clouds(state, dt)
    render_deck(state)
    render_scores(state^)
    render_player_cards(state)
    if (phase != GamePhase.EndGame) && (phase != GamePhase.EndRound) {
        render_deck(state)
        render_discard_pile(state)
    }

    rl.DrawText("SKYJO", SCREEN_WIDTH/2, SCREEN_HEIGHT/2, 20 * SCALE, rl.WHITE)
}

main :: proc() {
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "skyjo")
    defer rl.CloseWindow()

    rl.SetTargetFPS(60)

    state := init()
    defer deinit(&state)

    for !rl.WindowShouldClose() {
        if rl.IsKeyPressed(rl.KeyboardKey.P) {
            fmt.println("Taking screenshot")
            rl.TakeScreenshot("./doc/screenshot.png")
        }

        if rl.IsKeyPressed(rl.KeyboardKey.R) {
            // Reset the game
            deinit(&state)
            state = init()
        }

        rl.BeginDrawing()
        defer rl.EndDrawing()

        rl.ClearBackground(rl.DARKBLUE)

        update(&state, rl.GetFrameTime())
    }
}

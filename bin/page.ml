(* The whole web UI, served as one self-contained page at "/".
   UNO pop-art theme: hero splash lobby, oval game table with opponents'
   card backs fanned around it, flying card animations. Gameplay is
   click-only; the single typing surface is the house-rules editor.
   NOTE: the byte sequence "| html}" (without the space) must never appear
   inside the string below — it would terminate the OCaml quoted literal. *)
let html =
  {html|<!doctype html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Custom UNO</title>
<style>
  :root {
    --c-red:#e0332c; --c-yellow:#ffce00; --c-blue:#0a6bbd; --c-green:#18a850;
    --ink:#161418; --paper:#fffdf7;
    --bg-red-1:#c2261f; --bg-red-2:#8f1613;
    --felt-1:#28797f; --felt-2:#123e42;
    --card-w: clamp(54px, 6.5vw, 82px);
    --mini-w: clamp(20px, 2.4vw, 30px);
    --shadow-card: 0 4px 10px rgba(0,0,0,.35);
    --ease-pop: cubic-bezier(.3,1.4,.4,1);
  }
  * { box-sizing:border-box; }
  html, body { height:100%; }
  body { font-family:system-ui,sans-serif; margin:0; color:#fff; background:var(--bg-red-2); overflow-x:hidden; }
  /* rotating pop-art sunburst behind the lobby */
  body::before { content:''; position:fixed; left:50%; top:50%; width:250vmax; height:250vmax;
    margin:-125vmax 0 0 -125vmax; z-index:-2;
    background:repeating-conic-gradient(var(--bg-red-1) 0 9deg, var(--bg-red-2) 9deg 18deg);
    animation:spin 90s linear infinite; }
  body::after { content:''; position:fixed; inset:0; z-index:-1; pointer-events:none;
    background:radial-gradient(circle at 50% 40%, transparent 30%, rgba(0,0,0,.55)); }
  @keyframes spin { to { transform:rotate(360deg); } }

  /* ============ cards ============ */
  .card { position:relative; display:inline-flex; align-items:center; justify-content:center;
    width:var(--card-w); height:calc(var(--card-w)*1.5);
    font-size:calc(var(--card-w)*.52); border-radius:calc(var(--card-w)*.13);
    background:var(--ink); color:#fff; box-shadow:var(--shadow-card);
    overflow:hidden; user-select:none; flex:none; }
  .card::before { content:''; position:absolute; inset:0; border-radius:inherit; z-index:3;
    box-shadow:inset 0 0 0 calc(var(--card-w)*.055) #fff; pointer-events:none; }
  .card .ellipse { position:absolute; width:150%; height:62%; left:50%; top:50%;
    transform:translate(-50%,-50%) rotate(-32deg); border-radius:50%;
    background:var(--paper); z-index:1; }
  .card .glyph { position:relative; z-index:2; font-weight:900; font-style:italic;
    text-shadow:.05em .05em 0 rgba(0,0,0,.25); line-height:1; }
  .card .ix { position:absolute; z-index:2; font-size:.3em; font-weight:900; font-style:italic;
    color:#fff; text-shadow:.1em .1em 0 rgba(0,0,0,.35); line-height:1; }
  .card .ix.tl { top:.5em; left:.6em; }
  .card .ix.br { bottom:.5em; right:.6em; transform:rotate(180deg); }
  .card.Red { background:var(--c-red); }     .card.Red .glyph { color:var(--c-red); }
  .card.Green { background:var(--c-green); } .card.Green .glyph { color:var(--c-green); }
  .card.Blue { background:var(--c-blue); }   .card.Blue .glyph { color:var(--c-blue); }
  .card.Yellow { background:var(--c-yellow); } .card.Yellow .glyph { color:#c79c00; }
  .card.NoColor .ellipse { background:conic-gradient(var(--c-red) 0 25%, var(--c-blue) 0 50%,
    var(--c-yellow) 0 75%, var(--c-green) 0); }
  .card.NoColor .glyph { color:#fff; text-shadow:.06em .06em 0 rgba(0,0,0,.6); }
  .card.back .ellipse { background:var(--c-red); }
  .card.back .glyph { color:var(--c-yellow); font-size:.62em; transform:rotate(-12deg);
    text-shadow:.06em .06em 0 rgba(0,0,0,.45); letter-spacing:.01em; }
  .card.mini { --card-w: var(--mini-w); box-shadow:0 2px 4px rgba(0,0,0,.4); }
  .flying { position:fixed; z-index:60; margin:0; pointer-events:none; }

  /* ============ hero (join + lobby) ============ */
  .hero { min-height:100dvh; display:flex; flex-direction:column; align-items:center;
    padding:5vh 16px 4vh; position:relative; z-index:1; }
  .deco { position:fixed; z-index:0; pointer-events:none; opacity:.92;
    animation:floaty 7s ease-in-out infinite; }
  @keyframes floaty { 50% { translate:0 -16px; } }
  .logo { position:relative; display:grid; place-items:center; transform:rotate(-6deg);
    width:min(380px,84vw); height:min(160px,36vw); border-radius:50%;
    background:var(--c-red); border:6px solid var(--c-yellow);
    box-shadow:inset 0 0 0 4px #fff, 0 12px 0 rgba(0,0,0,.25), 0 24px 50px rgba(0,0,0,.4); }
  .logo .uno { font-size:clamp(3rem,13vw,5.2rem); font-weight:900; font-style:italic;
    color:var(--c-yellow); -webkit-text-stroke:2px #fff;
    text-shadow:4px 4px 0 rgba(0,0,0,.3); letter-spacing:-.03em; }
  .logo .strip { position:absolute; bottom:-.9rem; background:var(--paper); color:var(--ink);
    font-weight:900; letter-spacing:.45em; padding:.25rem .9rem .25rem 1.2rem;
    border-radius:6px; transform:rotate(3deg); font-size:.9rem;
    box-shadow:0 4px 0 rgba(0,0,0,.25); }
  .panel { position:relative; z-index:2; width:min(520px,94vw);
    background:rgba(24,12,12,.62); backdrop-filter:blur(10px);
    border-radius:18px; border-top:6px solid var(--c-yellow);
    padding:1.1rem 1.4rem 1.3rem; margin-top:1.6rem;
    box-shadow:0 18px 50px rgba(0,0,0,.45); }
  .panel h2 { margin:.2rem 0 .8rem; font-style:italic; letter-spacing:.04em; }
  input, textarea { font:inherit; border-radius:10px; border:none; padding:.6rem .8rem; }
  textarea { width:100%; font-family:ui-monospace,monospace; font-size:.85rem;
    background:#140c0c; color:#ffe9c9; border:1px solid rgba(255,206,0,.25); }
  button { font:inherit; font-weight:800; border:none; border-radius:999px;
    padding:.6rem 1.4rem; cursor:pointer; background:var(--c-yellow); color:var(--ink);
    box-shadow:0 4px 0 rgba(0,0,0,.3); transition:transform .12s var(--ease-pop); }
  button:hover { transform:translateY(-2px) scale(1.03); }
  button:active { transform:translateY(1px); }
  .err { color:#ffd3d3; white-space:pre-wrap; font-family:ui-monospace,monospace; font-size:.85rem; }
  .ok { color:#c9f7d4; }
  #rules-status { border-radius:10px; padding:.5rem .7rem; margin:.6rem 0 0; }
  #rules-status.err { background:rgba(224,51,44,.25); }
  #rules-status.ok { background:rgba(24,168,80,.25); }
  #rules-status:empty { display:none; }
  ul#lobby-players { list-style:none; padding:0; margin:.2rem 0 1rem; display:flex;
    flex-wrap:wrap; gap:.5rem; }
  ul#lobby-players li { background:rgba(255,255,255,.14); border-radius:999px;
    padding:.35rem .9rem; font-weight:700; }
  /* rules editor helpers */
  .preset-row { display:flex; gap:.5rem; align-items:center; flex-wrap:wrap; margin-bottom:.5rem; }
  button.preset, button.small { padding:.3rem .8rem; font-size:.82rem;
    background:rgba(255,255,255,.92); box-shadow:0 2px 0 rgba(0,0,0,.3); }
  button.preset.toggle { background:rgba(255,255,255,.45); }
  button.preset.toggle.active { background:var(--c-yellow);
    box-shadow:inset 0 2px 2px rgba(0,0,0,.25); }
  button.preset.toggle.active::before { content:'\2713  '; font-weight:900; }
  #check-status { font-size:.83rem; margin:.25rem 0 .35rem; min-height:1.1rem;
    font-family:ui-monospace,monospace; white-space:pre-wrap; }
  #check-status.ok { color:#8fe3a8; } #check-status.err { color:#ffb0b0; }
  #check-status.warn { color:#ffd97a; white-space:pre-line; }
  #check-status button { margin-left:.5rem; padding:.05rem .5rem; font-size:.72rem; }
  #override-list { display:flex; flex-wrap:wrap; gap:.35rem; margin-top:.5rem; font-size:.83rem; }
  #override-list code { cursor:pointer; padding:.14rem .45rem; border-radius:6px;
    background:rgba(255,255,255,.1); }
  #override-list code:hover { background:rgba(255,206,0,.35); }
  .panel details { margin:.7rem 0 0; background:rgba(0,0,0,.28); border-radius:12px;
    padding:.55rem .9rem; }
  .panel summary { cursor:pointer; font-weight:800; }
  .b-row { display:flex; gap:.5rem; align-items:center; flex-wrap:wrap; margin:.6rem 0; }
  .b-row > label:first-child { font-weight:800; font-style:italic; width:3.4rem; }
  .b-row select, .b-row input[type=number], .b-row input[type=text],
  .b-row input:not([type]) { border-radius:8px; padding:.35rem .5rem; font-size:.88rem; }
  .b-row input[type=number] { width:4.2rem; }
  .b-check { font-size:.85rem; display:inline-flex; gap:.3rem; align-items:center; }
  #b-name { flex:1; min-width:8rem; }
  .chips { display:flex; flex-wrap:wrap; gap:.4rem; margin:.2rem 0 .2rem 3.9rem; }
  .chips:empty { display:none; }
  #b-preview { background:rgba(255,255,255,.08); border-radius:8px; padding:.5rem .7rem;
    margin:.5rem 0 0; font-size:.8rem; white-space:pre-wrap; }
  #b-preview:empty { display:none; }
  .chips span { background:var(--c-yellow); color:var(--ink); font-weight:700;
    font-size:.78rem; border-radius:999px; padding:.2rem .6rem; cursor:pointer; }
  .chips span::after { content:' ✕'; opacity:.6; }
  .cheat { display:grid; grid-template-columns:1fr 1fr; gap:.8rem; font-size:.83rem;
    margin-top:.5rem; }
  .cheat h4 { margin:.2rem 0 .3rem; }
  .cheat code { display:block; cursor:pointer; padding:.14rem .45rem; border-radius:6px;
    background:rgba(255,255,255,.1); margin:.18rem 0; }
  .cheat code:hover { background:rgba(255,206,0,.35); }
  .cheat-shape { background:rgba(255,255,255,.08); border-radius:8px; padding:.5rem .7rem;
    font-size:.8rem; margin:.5rem 0 0; }
  @media (min-width:1000px){
    .lobby-grid { display:grid; grid-template-columns:1fr 1fr; gap:1.2rem;
      width:min(1060px,96vw); align-items:start; }
    .lobby-grid .panel { width:auto; }
  }

  /* ============ game view ============ */
  #view-game { position:fixed; inset:0; overflow:hidden; z-index:2;
    background:radial-gradient(circle at 50% 15%, #35333f, #141319 70%); }
  #table-oval { position:absolute; left:50%; top:50%; transform:translate(-50%,-52%);
    width:min(80vw,900px); height:min(54vh,480px); border-radius:50%;
    background:radial-gradient(ellipse at 50% 32%, var(--felt-1), var(--felt-2));
    box-shadow:inset 0 0 70px rgba(0,0,0,.5), 0 0 0 12px var(--c-red),
      0 0 0 16px rgba(255,255,255,.9), 0 30px 70px rgba(0,0,0,.55); }
  .table-center { position:absolute; left:50%; top:48%; transform:translate(-50%,-50%);
    display:flex; align-items:center; gap:calc(var(--card-w)*.5); z-index:2; }
  .pile { position:relative; width:var(--card-w); height:calc(var(--card-w)*1.5); }
  .pile .card { position:absolute; inset:0; }
  #draw-pile { cursor:pointer; }
  #draw-pile .card:nth-child(1){ transform:translate(-4px,4px) rotate(-4deg); }
  #draw-pile .card:nth-child(2){ transform:translate(2px,-1px) rotate(2deg); }
  #draw-pile:hover .card:nth-child(3){ transform:translateY(-8px); }
  #draw-pile .card { transition:transform .15s; }
  #discard { border-radius:calc(var(--card-w)*.13);
    box-shadow:0 0 0 5px var(--cur,#333), 0 0 26px var(--cur,transparent);
    transition:box-shadow .35s; }
  #discard .card { transform:rotate(var(--tilt,0deg)); }
  #discard.color-pop { animation:colorpop .55s var(--ease-pop); }
  @keyframes colorpop { 35% { transform:scale(1.16); } }
  #pending-badge { position:absolute; top:-12px; right:-12px; z-index:5;
    background:var(--c-red); color:#fff; font-weight:900; font-size:1rem;
    border-radius:999px; padding:.25rem .6rem; border:3px solid #fff;
    box-shadow:0 4px 8px rgba(0,0,0,.4); animation:pulse 1s ease-in-out infinite; }
  #seats { position:absolute; inset:0; z-index:3; pointer-events:none; }
  .seat { position:absolute; transform:translate(-50%,-50%); text-align:center; }
  .seat .fan { display:flex; justify-content:center; align-items:flex-end;
    height:calc(var(--mini-w)*1.9); }
  .seat .fan .card { margin-left:calc(var(--mini-w)*-.55); }
  .seat .fan .card:first-child { margin-left:0; }
  .seat .plate { display:inline-flex; align-items:center; gap:.4rem; margin-top:5px;
    background:rgba(0,0,0,.6); border-radius:999px; padding:.22rem .8rem;
    font-weight:800; font-size:.85rem; white-space:nowrap; }
  .seat.turn { filter:drop-shadow(0 0 14px rgba(255,206,0,.85)); }
  .seat.turn .plate { background:var(--c-yellow); color:var(--ink); animation:pulse 1.2s ease-in-out infinite; }
  @keyframes pulse { 50% { transform:scale(1.07); } }
  .count { display:inline-block; min-width:1.4rem; text-align:center;
    background:rgba(255,255,255,.25); border-radius:999px; padding:0 .35rem; font-size:.8rem; }
  .seat.turn .count { background:rgba(0,0,0,.2); }
  .count.uno { background:var(--c-red); color:#fff; animation:unopop .4s var(--ease-pop); }
  @keyframes unopop { from { transform:scale(0); } }
  #turn-banner { position:absolute; left:50%; bottom:calc(var(--card-w)*1.5 + 74px);
    transform:translateX(-50%); z-index:6; background:var(--c-yellow); color:var(--ink);
    font-weight:900; font-style:italic; letter-spacing:.08em; padding:.35rem 1.2rem;
    border-radius:999px; box-shadow:0 4px 0 rgba(0,0,0,.3); animation:pulse 1.2s ease-in-out infinite; }
  #hand-area { position:absolute; left:0; right:0; bottom:0; z-index:5;
    display:flex; align-items:flex-end; justify-content:center; gap:1rem;
    padding:0 12px 16px; pointer-events:none; }
  #hand-area > * { pointer-events:auto; }
  #hand { position:relative; white-space:nowrap; height:calc(var(--card-w)*1.85); display:flex; align-items:flex-end; }
  .slot { display:inline-block; position:relative; }
  .slot + .slot { margin-left:calc(-1 * var(--overlap,20px)); }
  .slot .card { transform:rotate(var(--rot,0deg)) translateY(calc(var(--ty,0px) + var(--lift,0px)));
    transform-origin:50% 130%; transition:transform .25s var(--ease-pop), box-shadow .25s, filter .25s; cursor:pointer; }
  .slot:hover { z-index:7; }
  #hand .card { touch-action:none; cursor:grab; }
  .slot.dragging { z-index:9; }
  .slot.dragging .card, .slot.dragging:hover .card {
    transform:translate(var(--dx,0px), calc(var(--dy,0px) - 24px)) scale(1.08);
    transition:none; box-shadow:0 18px 34px rgba(0,0,0,.55); }
  .slot:hover .card { transform:rotate(var(--rot,0deg)) translateY(calc(var(--ty,0px) - 28px)) scale(1.12); }
  /* on your turn: playable cards lift with a white glow, unplayable dim */
  #hand.my-turn .slot:not(.playable) .card { filter:grayscale(.4) brightness(.72); }
  .slot.playable .card { --lift:-16px;
    box-shadow:0 8px 16px rgba(0,0,0,.45), 0 0 0 3px #fff, 0 0 18px rgba(255,255,255,.7); }
  /* playable AND part of a same-value stack you could chain: gold pulse */
  .slot.stackable .card { box-shadow:0 8px 16px rgba(0,0,0,.45),
      0 0 0 3px var(--c-yellow), 0 0 24px rgba(255,206,0,.95);
    animation:stackpulse 1.1s ease-in-out infinite; }
  @keyframes stackpulse { 50% { box-shadow:0 8px 16px rgba(0,0,0,.45),
      0 0 0 5px var(--c-yellow), 0 0 34px rgba(255,206,0,1); } }
  #pass-btn { margin-bottom:calc(var(--card-w)*.4); }
  #leave-game { position:absolute; top:12px; right:14px; z-index:6;
    background:rgba(0,0,0,.5); color:#fff; font-size:.85rem; font-weight:800;
    box-shadow:0 3px 0 rgba(0,0,0,.35); }
  #leave-game:hover { background:var(--c-red); }
  button.leave { background:rgba(255,255,255,.18); color:#fff; }
  #log { position:absolute; left:14px; bottom:12px; z-index:4; list-style:none; margin:0;
    padding:0; font-size:.78rem; opacity:.75; max-width:230px; }
  #log li { padding:.12rem 0; border-bottom:1px solid rgba(255,255,255,.12); }
  #game-logo { position:absolute; top:10px; left:16px; z-index:4; font-weight:900;
    font-style:italic; color:var(--c-yellow); -webkit-text-stroke:1px #fff;
    font-size:1.5rem; text-shadow:2px 2px 0 rgba(0,0,0,.4); transform:rotate(-4deg); }
  #game-code { position:absolute; top:46px; left:18px; z-index:4; font-weight:800;
    letter-spacing:.25em; opacity:.75; font-size:.85rem; }
  .code-chip { display:inline-block; background:var(--c-yellow); color:var(--ink);
    border-radius:8px; padding:.05rem .6rem .05rem .8rem; letter-spacing:.3em;
    font-style:normal; vertical-align:middle; }

  /* ============ overlays ============ */
  #toast { position:fixed; top:14px; left:50%; transform:translateX(-50%) translateY(-80px);
    background:var(--c-red); color:#fff; font-weight:800; padding:.55rem 1.2rem;
    border-radius:999px; box-shadow:0 6px 0 rgba(0,0,0,.3); z-index:70;
    transition:transform .3s var(--ease-pop); pointer-events:none; max-width:88vw; }
  #toast.show { transform:translateX(-50%) translateY(0); }
  #turn-countdown { position:fixed; top:14px; left:50%; transform:translateX(-50%);
    background:var(--ink); color:#fff; font-weight:800; padding:.5rem 1.1rem .5rem .7rem;
    border-radius:999px; border:3px solid var(--c-red); z-index:65;
    display:flex; align-items:center; gap:.55rem;
    box-shadow:0 6px 0 rgba(0,0,0,.3), 0 0 22px rgba(224,51,44,.55);
    animation:cdpop .25s var(--ease-pop); pointer-events:none; max-width:88vw; }
  #turn-countdown .num { background:var(--c-red); color:#fff; font-weight:900;
    font-size:1.15rem; width:2rem; height:2rem; border-radius:50%; flex:none;
    display:grid; place-items:center; animation:pulse .5s ease-in-out infinite; }
  @keyframes cdpop { from { transform:translateX(-50%) scale(.6); opacity:0; } }
  #color-modal { position:fixed; inset:0; background:rgba(0,0,0,.65);
    display:flex; align-items:center; justify-content:center; z-index:30; }
  #color-modal .wheel { width:min(300px,74vw); aspect-ratio:1; border-radius:50%;
    overflow:hidden; display:grid; grid-template:1fr 1fr / 1fr 1fr; gap:8px; padding:8px;
    background:var(--paper); transform:rotate(45deg);
    box-shadow:0 0 0 6px #fff, 0 20px 60px rgba(0,0,0,.5);
    animation:wheelin .35s var(--ease-pop); }
  @keyframes wheelin { from { transform:rotate(45deg) scale(.5); opacity:0; } }
  #color-modal .wheel button { border-radius:12px; box-shadow:none; padding:0; }
  #color-modal .wheel button:hover { transform:scale(1.05); }
  .swatch-red{background:var(--c-red)} .swatch-green{background:var(--c-green)}
  .swatch-blue{background:var(--c-blue)} .swatch-yellow{background:var(--c-yellow)}
  #uno-splash { position:fixed; left:50%; top:38%; transform:translate(-50%,-50%) rotate(-6deg);
    z-index:40; font-size:clamp(2.5rem,9vw,4.5rem); font-weight:900; font-style:italic;
    color:var(--c-yellow); -webkit-text-stroke:2px #fff;
    text-shadow:5px 5px 0 rgba(0,0,0,.4); pointer-events:none;
    animation:unopop .45s var(--ease-pop); }
  /* big event splash: SKIPPED! / DRAW N! for the affected player,
     REVERSED for the whole table */
  .event-splash { position:fixed; left:50%; top:36%; z-index:45; pointer-events:none;
    text-align:center; font-weight:900; font-style:italic;
    transform:translate(-50%,-50%) rotate(-5deg);
    animation:splashlife 1.8s var(--ease-pop) forwards; }
  .event-splash .sym { font-size:clamp(4rem,16vw,7.5rem); line-height:1;
    -webkit-text-stroke:3px #fff; text-shadow:6px 6px 0 rgba(0,0,0,.45); }
  .event-splash .lbl { font-size:clamp(1.1rem,4vw,1.9rem); letter-spacing:.28em;
    margin-top:.2rem; text-shadow:3px 3px 0 rgba(0,0,0,.45); color:#fff; }
  .event-splash.red { color:var(--c-red); }
  .event-splash.blue { color:var(--c-blue); }
  .event-splash.mid .sym { font-size:clamp(2.6rem,10vw,4.6rem); }
  .event-splash.spin .sym { display:inline-block; animation:spinonce .9s var(--ease-pop); }
  @keyframes splashlife {
    0% { opacity:0; transform:translate(-50%,-50%) scale(0) rotate(-14deg); }
    12% { opacity:1; transform:translate(-50%,-50%) scale(1.18) rotate(-4deg); }
    20% { transform:translate(-50%,-50%) scale(1) rotate(-5deg); }
    78% { opacity:1; }
    100% { opacity:0; transform:translate(-50%,-50%) scale(1.06) rotate(-5deg); } }
  @keyframes spinonce { to { transform:rotate(360deg); } }
  /* smaller signal over an opponent's seat */
  .seat-badge { position:absolute; left:50%; top:-10px; z-index:6;
    transform:translate(-50%,-100%); font-weight:900; font-size:.95rem;
    padding:.3rem .75rem; border-radius:999px; border:2px solid #fff;
    box-shadow:0 4px 10px rgba(0,0,0,.45); white-space:nowrap; pointer-events:none;
    animation:badgelife 1.6s var(--ease-pop) forwards; }
  .seat-badge.skip { background:var(--c-red); color:#fff; }
  .seat-badge.penalty { background:var(--ink); color:var(--c-yellow); }
  @keyframes badgelife {
    0% { opacity:0; transform:translate(-50%,-60%) scale(0); }
    14% { opacity:1; transform:translate(-50%,-105%) scale(1.15); }
    24% { transform:translate(-50%,-100%) scale(1); }
    72% { opacity:1; }
    100% { opacity:0; transform:translate(-50%,-145%) scale(.9); } }
  #win-overlay { position:fixed; inset:0; z-index:50; background:rgba(10,6,10,.82);
    display:flex; flex-direction:column; align-items:center; justify-content:center; gap:1.4rem;
    overflow:hidden; }
  #win-overlay .win-name { font-size:clamp(2.6rem,10vw,5rem); font-weight:900; font-style:italic;
    color:var(--c-yellow); -webkit-text-stroke:2px #fff; text-shadow:5px 5px 0 rgba(0,0,0,.45);
    transform:rotate(-5deg); animation:unopop .5s var(--ease-pop); }
  #win-overlay .win-sub { font-size:1.4rem; font-weight:800; letter-spacing:.2em; }
  #win-overlay i { position:absolute; top:-8vh; width:10px; height:16px; border-radius:2px;
    left:var(--x); animation:fall var(--d) linear var(--dl) infinite; }
  @keyframes fall { to { transform:translateY(120vh) rotate(720deg); } }
  .c1{background:var(--c-red)} .c2{background:var(--c-yellow)}
  .c3{background:var(--c-blue)} .c4{background:var(--c-green)}
  [hidden] { display:none !important; }

  @media (max-width:760px){
    #table-oval { width:96vw; height:44vh; }
    #log { display:none; }
    .seat .plate { font-size:.72rem; padding:.15rem .55rem; }
    :root { --mini-w:18px; }
  }
  @media (prefers-reduced-motion: reduce){
    *, *::before, *::after { animation:none !important; transition:none !important; }
  }
</style>
</head>
<body>
<div id="toast"></div>

<div id="hero" class="hero" aria-label="CUSTOM UNO">
  <div class="deco card back" style="--card-w:96px; left:6vw; top:12vh; rotate:-14deg; animation-delay:-2s"><span class="ellipse"></span><span class="glyph">UNO</span></div>
  <div class="deco card Red" style="--card-w:76px; right:8vw; top:9vh; rotate:12deg; animation-delay:-4s"><span class="ellipse"></span><span class="glyph">7</span></div>
  <div class="deco card Blue" style="--card-w:64px; left:12vw; bottom:14vh; rotate:9deg; animation-delay:-1s"><span class="ellipse"></span><span class="glyph">+2</span></div>
  <div class="deco card Yellow" style="--card-w:88px; right:10vw; bottom:10vh; rotate:-8deg; animation-delay:-5s"><span class="ellipse"></span><span class="glyph">⇄</span></div>
  <div class="deco card Green" style="--card-w:58px; left:38vw; top:6vh; rotate:5deg; animation-delay:-3s"><span class="ellipse"></span><span class="glyph">⊘</span></div>
  <div class="deco card NoColor" style="--card-w:70px; right:34vw; bottom:6vh; rotate:-5deg; animation-delay:-6s"><span class="ellipse"></span><span class="glyph">W</span></div>

  <div class="logo"><span class="uno">UNO</span><span class="strip">CUSTOM</span></div>

  <div id="view-join" class="panel" style="text-align:center">
    <h2>Pull up a chair</h2>
    <input id="name-input" placeholder="your name" maxlength="20">
    <div style="margin:1rem 0 .4rem"><button id="host-btn">Host a new lobby</button></div>
    <div style="opacity:.7; font-weight:800; margin:.5rem 0">— or join with a code —</div>
    <div style="display:flex; gap:.5rem; justify-content:center">
      <input id="code-input" placeholder="CODE" maxlength="4"
             style="width:7.5rem; text-transform:uppercase; text-align:center;
                    font-weight:800; letter-spacing:.3em">
      <button id="join-btn">Join</button>
    </div>
    <div id="join-err" class="err" style="margin-top:.6rem"></div>
  </div>

  <div id="view-lobby" class="lobby-grid" hidden>
    <div class="panel">
      <h2>Lobby <span id="room-code" class="code-chip"></span></h2>
      <p style="margin:.1rem 0 .8rem">
        <button id="copy-link" class="small">Copy invite link</button>
        <span id="copy-done" class="ok"></span>
      </p>
      <ul id="lobby-players"></ul>
      <button id="start-btn">Start game</button>
      <button id="leave-lobby" class="leave">Leave lobby</button>
      <div id="lobby-status" class="ok" style="margin-top:.6rem"></div>
    </div>
    <div class="panel">
      <h2>House rules</h2>
      <div class="preset-row">
        <span style="opacity:.8">Preset:</span>
        <button class="preset" id="preset-standard">Standard</button>
        <span style="opacity:.8">+ toggles:</span>
        <button class="preset toggle" id="toggle-stacking">Stacking</button>
        <button class="preset toggle" id="toggle-drawuntil">Draw until playable</button>
      </div>
      <div id="check-status"></div>
      <textarea id="rules-text" rows="12" spellcheck="false"></textarea>

      <details id="builder">
        <summary>🛠 Compose a new rule without typing</summary>
        <div class="b-row"><label>When</label>
          <select id="b-when"></select>
          <input id="b-when-n" type="number" value="0" min="0" hidden>
          <label class="b-check"><input id="b-not" type="checkbox"> not</label>
          <button id="b-add-cond" class="small">+ add condition</button>
        </div>
        <div id="b-conds" class="chips"></div>
        <div class="b-row"><label>Then</label>
          <select id="b-eff"></select>
          <input id="b-eff-n" type="number" value="2" min="1" hidden>
          <select id="b-eff-color" hidden>
            <option>red</option><option>yellow</option>
            <option>green</option><option>blue</option>
          </select>
          <button id="b-add-eff" class="small">+ add effect</button>
        </div>
        <div id="b-effs" class="chips"></div>
        <pre id="b-preview"></pre>
        <div class="b-row"><label>Extras</label>
          <select id="b-prio">
            <option value="50" selected>normal priority</option>
            <option value="100">same as the special cards</option>
            <option value="115">high — beats the special cards</option>
            <option value="5">low — a fallback rule</option>
          </select>
          <input id="b-name" placeholder="rule name (optional)">
          <button id="b-append">Add to ruleset</button>
        </div>
        <p style="opacity:.7; font-size:.8rem; margin:.3rem 0 0">Stack as many conditions
        as you like — they must all hold ("and"). Tick "not" to require the opposite of
        the next condition. Picking a card condition pre-adds the usual play effects.
        Click any chip to remove it.</p>
      </details>

      <details id="override">
        <summary>🔁 Change a built-in rule</summary>
        <p style="opacity:.75; font-size:.82rem; margin:.3rem 0 0">Click a rule to copy it
        into the editor, then tweak its effects. Your copy keeps the same name, so it
        replaces the built-in version.</p>
        <div id="override-list"></div>
      </details>

      <details>
        <summary>📖 Cheat sheet</summary>
        <pre class="cheat-shape">rule "name" priority 100:
  when &lt;condition&gt;
  do &lt;effect&gt;, &lt;effect&gt;</pre>
        <div class="cheat">
          <div>
            <h4>Presets (click to insert)</h4>
            <code>use standard</code>
            <code>use stacking</code>
            <code>use draw until playable</code>
            <code>use stacking with draw until playable</code>
            <h4 style="margin-top:.6rem">Conditions (click to insert)</h4>
            <code>card matches color</code>
            <code>card matches value</code>
            <code>card is wild</code>
            <code>card is skip</code>
            <code>card is reverse</code>
            <code>card is plus two</code>
            <code>card is plus four</code>
            <code>player draws</code>
            <code>player passes</code>
            <code>continues stack</code>
            <code>stack is open</code>
            <code>drew playable card</code>
            <code>pending draws > 0</code>
            <code>your turn</code>
            <code>always</code>
          </div>
          <div>
            <h4>Effects (click to insert)</h4>
            <code>play the card</code>
            <code>set color from card</code>
            <code>set color to declared</code>
            <code>set color to red</code>
            <code>draw 2 cards</code>
            <code>draw and decide</code>
            <code>next player draws 2 cards</code>
            <code>add 2 pending draws</code>
            <code>apply pending draws</code>
            <code>draw until playable</code>
            <code>reverse direction</code>
            <code>skip next player</code>
            <code>open stack</code>
            <code>close stack</code>
            <code>advance turn</code>
          </div>
        </div>
        <p style="opacity:.75; font-size:.82rem">Join conditions with <b>and</b> / <b>or</b> / <b>not</b>, parentheses to group. Higher priority wins when several rules match.</p>
      </details>

      <p style="margin:.7rem 0 0"><button id="rules-btn">Submit rules</button></p>
      <pre id="rules-status"></pre>
    </div>
  </div>
</div>

<div id="view-game" hidden>
  <div id="game-logo">UNO</div>
  <div id="game-code"></div>
  <button id="leave-game">Leave game</button>
  <div id="table-oval"></div>
  <div id="seats"></div>
  <div class="table-center">
    <div id="draw-pile" class="pile" title="draw a card">
      <span id="pending-badge" hidden></span>
    </div>
    <div id="discard" class="pile"></div>
  </div>
  <div id="turn-banner" hidden>YOUR TURN</div>
  <div id="turn-countdown" hidden><span class="num"></span><span class="msg"></span></div>
  <div id="hand-area">
    <div id="hand"></div>
    <button id="pass-btn" hidden>Done</button>
  </div>
  <ul id="log"></ul>
</div>

<div id="color-modal" hidden>
  <div class="wheel">
    <button class="swatch-red" data-color="red"></button>
    <button class="swatch-yellow" data-color="yellow"></button>
    <button class="swatch-green" data-color="green"></button>
    <button class="swatch-blue" data-color="blue"></button>
  </div>
</div>

<div id="uno-splash" hidden></div>
<div id="win-overlay" hidden>
  <div class="win-name"></div>
  <div class="win-sub">WINS THE GAME</div>
  <button id="win-back">Back to lobby</button>
</div>

<script>
const VALUE_LABEL = {Zero:'0',One:'1',Two:'2',Three:'3',Four:'4',Five:'5',Six:'6',
  Seven:'7',Eight:'8',Nine:'9',Skip:'⊘',Reverse:'⇄',Plus:'+2',Wild:'W',Wild4:'+4'};
const COLOR_CSS = {Red:'#e0332c',Green:'#18a850',Blue:'#0a6bbd',Yellow:'#ffce00',NoColor:'#333'};

// the preset toggles compose the ruleset through the server-side `use`
// shortcut; the rules a `use` line expands to live in lib/presets.ml and
// are documented in docs/rule-language.md
const PRESET_DESC = {
  'standard': 'Standard Uno.',
  'stacking': 'Stacking: chain same-value cards in one turn, click Done to end it.',
  'draw until playable':
    'Draw-until: when you cannot play, keep drawing (one card per click) until you can.',
  'stacking with draw until playable':
    'Stacking + draw-until: chain same-value cards; when stuck, keep drawing until you can play.',
};
function presetName(){
  const s = $('toggle-stacking').classList.contains('active');
  const d = $('toggle-drawuntil').classList.contains('active');
  return s && d ? 'stacking with draw until playable'
       : s ? 'stacking' : d ? 'draw until playable' : 'standard';
}
function presetText(){
  const name = presetName();
  return '# ' + PRESET_DESC[name] + '\n' +
    'use ' + name + '\n\n' +
    '# Add house rules below - they combine with the preset above.\n' +
    '# Redefining a rule with the same name replaces the preset version.\n';
}

const WHEN_OPTIONS = [
  ['card matches color or card matches value', 'a matching card is played'],
  ['card matches color', 'the played card matches the color'],
  ['card matches value', 'the played card matches the value'],
  ['card is plus two', 'a +2 is played'],
  ['card is plus four', 'a +4 is played'],
  ['card is skip', 'a skip is played'],
  ['card is reverse', 'a reverse is played'],
  ['card is wild', 'a wild is played'],
  ['player draws', 'the player clicks draw'],
  ['player passes', 'the player clicks done'],
  ['continues stack', 'a card continues the stack'],
  ['stack is open', 'a stack is open'],
  ['drew playable card', 'the drawn card is playable'],
  ['pending draws > N', 'penalty draws are pending'],
  ['always', 'always (any action)'],
];
const EFF_OPTIONS = [
  ['play the card', 'play the card'],
  ['advance turn', 'end the turn'],
  ['set color from card', 'set color from the card'],
  ['set color to declared', 'set color to the declared color (wilds)'],
  ['set color to C', 'set color to a specific color'],
  ['draw N cards', 'draw some cards'],
  ['draw and decide', 'draw 1; keep turn if playable'],
  ['next player draws N cards', 'next player draws cards now'],
  ['add N pending draws', 'add penalty draws (stackable)'],
  ['apply pending draws', 'apply the pending penalty'],
  ['draw until playable', 'draw 1; flag a playable draw'],
  ['reverse direction', 'reverse direction'],
  ['skip next player', 'skip the next player'],
  ['open stack', 'open a stack: stay on turn, chain that value'],
  ['close stack', 'close the stack (Done does this)'],
];

let name = null;
let code = null;
const freshState = () => ({ players:[], hand:[], top:null, color:null, current:null,
              counts:{}, inGame:false, pileStack:[], pending:0,
              canPass:false, stackValue:null, stacking:false });
let state = freshState();
let pendingWild = null;
let lastPlayedId = null;
let snapshotMode = false;
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
const dirty = { lobby:false, seats:false, pile:false, hand:false, turn:false };

const $ = id => document.getElementById(id);
const rect = el => el.getBoundingClientRect();

/* ---------- card factories ---------- */
function cardEl(card, mini){
  const el = document.createElement('div');
  // a played card wears the active color (card.declared) when it differs
  // from the printed one - declared wilds, or a rule that recolors the pile
  const color = card.declared || card.color;
  el.className = 'card ' + color + (mini ? ' mini' : '');
  el.dataset.cid = card.id;
  const label = VALUE_LABEL[card.value] || card.value;
  el.innerHTML = '<span class="ix tl"></span><span class="ellipse"></span>' +
                 '<span class="glyph"></span><span class="ix br"></span>';
  el.querySelector('.glyph').textContent = label;
  el.querySelector('.ix.tl').textContent = label;
  el.querySelector('.ix.br').textContent = label;
  return el;
}
function cardBackEl(mini){
  const el = document.createElement('div');
  el.className = 'card back' + (mini ? ' mini' : '');
  el.innerHTML = '<span class="ellipse"></span><span class="glyph">UNO</span>';
  return el;
}
const tiltOf = id => ((id * 37) % 21) - 10;   // deterministic messy-pile tilt

/* ---------- small ui helpers ---------- */
function toast(msg){
  const t = $('toast'); t.textContent = msg; t.classList.add('show');
  clearTimeout(t._h); t._h = setTimeout(() => t.classList.remove('show'), 3000);
}
function logLine(msg){
  const li = document.createElement('li'); li.textContent = msg;
  const log = $('log'); log.prepend(li);
  while (log.children.length > 6) log.lastChild.remove();
}
function setView(v){
  $('hero').hidden = v === 'game';
  $('view-join').hidden = v !== 'join';
  $('view-lobby').hidden = v !== 'lobby';
  $('view-game').hidden = v !== 'game';
}
function unoSplash(who){
  const s = $('uno-splash'); s.textContent = 'UNO! ' + who; s.hidden = false;
  clearTimeout(s._h); s._h = setTimeout(() => { s.hidden = true; }, 1700);
}
// server-driven turn countdown: ticks locally, cleared by the next action
let cdTimer = null;
function showCountdown(player, seconds){
  const el = $('turn-countdown');
  const render = s => {
    el.querySelector('.num').textContent = s;
    el.querySelector('.msg').textContent = player === name
      ? 'play now or a card is played for you!'
      : player + ' is out of time soon…';
  };
  clearInterval(cdTimer);
  let s = seconds; render(s); el.hidden = false;
  cdTimer = setInterval(() => { s--; if (s < 1) hideCountdown(); else render(s); }, 1000);
}
function hideCountdown(){
  clearInterval(cdTimer); cdTimer = null; $('turn-countdown').hidden = true;
}
// big center-stage event splash (symbol + label); delay staggers a batch
function bigSplash(sym, label, cls, delay){
  setTimeout(() => {
    const el = document.createElement('div');
    el.className = 'event-splash ' + (cls || '');
    el.innerHTML = '<div class="sym"></div><div class="lbl"></div>';
    el.querySelector('.sym').textContent = sym;
    el.querySelector('.lbl').textContent = label;
    document.body.append(el);
    setTimeout(() => el.remove(), 1900);
  }, delay || 0);
}
// smaller but noticeable signal above an opponent's seat
function seatBadge(player, text, cls){
  const s = seatOf(player);
  if (!s) return;
  const b = document.createElement('div');
  b.className = 'seat-badge ' + (cls || '');
  b.textContent = text;
  s.append(b);
  setTimeout(() => b.remove(), 1700);
}
function showWin(winner){
  const w = $('win-overlay');
  w.querySelector('.win-name').textContent = winner;
  if (!w.querySelector('i')){
    for (let i = 0; i < 40; i++){
      const f = document.createElement('i');
      f.className = 'c' + (1 + i % 4);
      f.style.setProperty('--x', (Math.random() * 100) + 'vw');
      f.style.setProperty('--d', (2.4 + Math.random() * 2.4) + 's');
      f.style.setProperty('--dl', (-Math.random() * 4) + 's');
      w.append(f);
    }
  }
  w.hidden = false;
}

async function api(path, opts = {}){
  const sep = path.includes('?') ? '&' : '?';
  const ident = 'name=' + encodeURIComponent(name) + '&code=' + encodeURIComponent(code);
  const res = await fetch(path + sep + ident, opts);
  return res.json();
}

/* ---------- event reducer: mutates state, collects animation intents ---------- */
function apply(ev, fx){
  switch (ev.type){
    case 'lobby':
      state.players = ev.players; dirty.lobby = true;
      if (!state.inGame) setView('lobby');
      break;
    case 'game_started':
      hideCountdown();
      handOrder = [];
      lastPileColor = null; lastPileTopId = null;
      state.inGame = true; state.hand = orderedHand(ev.hand); state.top = ev.top_card;
      state.color = ev.current_color; state.players = ev.players;
      state.current = ev.current_player; state.counts = {};
      state.pileStack = [ev.top_card]; state.pending = ev.pending || 0;
      state.stacking = !!ev.stacking; state.canPass = false; state.stackValue = null;
      dirty.seats = dirty.pile = dirty.hand = dirty.turn = true;
      $('log').innerHTML = ''; $('win-overlay').hidden = true;
      setView('game'); layoutSeats();
      break;
    case 'hand': {
      if (fx){
        const oldIds = new Set(state.hand.map(c => c.id));
        const fresh = ev.hand.filter(c => !oldIds.has(c.id));
        if (fresh.length && !fx.some(f => f.kind === 'ownPlay'))
          fresh.forEach((c, i) => fx.push({kind:'ownDraw', id:c.id, delay:i*90,
                                           from:rect($('draw-pile'))}));
      }
      state.hand = orderedHand(ev.hand); dirty.hand = true;
      break;
    }
    case 'pile': {
      if (ev.current_color !== 'NoColor' && ev.top_card.color !== ev.current_color)
        ev.top_card.declared = ev.current_color;
      const changed = !state.top || state.top.id !== ev.top_card.id;
      if (changed){
        if (fx){
          if (ev.top_card.id === lastPlayedId){
            const el = document.querySelector('#hand .slot[data-cid="' + lastPlayedId + '"]');
            fx.push({kind:'ownPlay', card:ev.top_card, from: el ? rect(el) : null});
          } else {
            const seat = seatOf(state.current);
            fx.push({kind:'oppPlay', card:ev.top_card,
                     from: seat ? rect(seat) : rect($('draw-pile'))});
          }
        }
        lastPlayedId = null;
        state.pileStack.push(ev.top_card);
        if (state.pileStack.length > 4) state.pileStack.shift();
      }
      state.top = ev.top_card; state.color = ev.current_color;
      state.pending = ev.pending || 0; dirty.pile = true;
      break;
    }
    case 'turn':
      state.current = ev.player;
      state.canPass = !!ev.can_pass;
      state.stackValue = ev.stack_value || null;
      hideCountdown(); // an action landed, so the clock restarted
      dirty.turn = dirty.seats = true;
      break;
    case 'countdown':
      showCountdown(ev.player, ev.seconds);
      logLine((ev.player === name ? 'you have' : ev.player + ' has') +
              ' ' + ev.seconds + 's left');
      break;
    case 'hand_counts': {
      if (fx){
        for (const [p, n] of ev.counts){
          const old = state.counts[p];
          if (old !== undefined && n > old && p !== name)
            fx.push({kind:'oppDraw', player:p, count:n-old, from:rect($('draw-pile'))});
        }
      }
      state.counts = Object.fromEntries(ev.counts); dirty.seats = true;
      break;
    }
    case 'uno': unoSplash(ev.player); logLine('UNO! ' + ev.player); break;
    case 'skipped':
      logLine((ev.player === name ? 'you were' : ev.player + ' was') + ' skipped');
      if (fx) fx.push({kind:'skipped', player:ev.player});
      break;
    case 'forced_draw':
      logLine((ev.player === name ? 'you draw ' : ev.player + ' draws ') + ev.count);
      if (fx) fx.push({kind:'penalty', player:ev.player, count:ev.count});
      break;
    case 'direction':
      logLine('direction reversed');
      if (fx) fx.push({kind:'reversed'});
      break;
    case 'game_over':
      state.inGame = false;
      hideCountdown();
      $('lobby-status').textContent = 'Last game: ' + ev.winner + ' won';
      showWin(ev.winner);
      break;
    case 'rules_updated':
      $('rules-status').textContent = ev.player + ' set ' + ev.num_rules + ' house rules';
      $('rules-status').className = 'ok';
      logLine(ev.player + ' updated the rules');
      break;
    case 'rejected': toast(ev.reason); break;
  }
}

/* ---------- playable / stackable helpers ---------- */
const NUMBER_VALUES = new Set(['Zero','One','Two','Three','Four','Five',
                               'Six','Seven','Eight','Nine']);

function isPlayable(card){
  if (state.stackValue) return card.value === state.stackValue;
  if (state.pending > 0)
    // only stacking another +2/+4 dodges a pending penalty
    return card.value === 'Wild4' ||
           (card.value === 'Plus' &&
            (card.color === state.color || (state.top && state.top.value === 'Plus')));
  if (card.value === 'Wild' || card.value === 'Wild4') return true;
  return card.color === state.color || (state.top && card.value === state.top.value);
}

// lift + glow every playable card; gold-pulse the ones that can be chained
// as a same-value stack (only meaningful when the ruleset can open stacks)
function updateHighlights(){
  const myTurn = state.inGame && state.current === name;
  const copies = {};
  for (const c of state.hand) copies[c.value] = (copies[c.value] || 0) + 1;
  for (const slot of $('hand').children){
    const card = state.hand.find(c => String(c.id) === slot.dataset.cid);
    const playable = !!(myTurn && card && isPlayable(card));
    const stackable = playable && state.stacking && NUMBER_VALUES.has(card.value) &&
      (state.stackValue ? true : copies[card.value] > 1);
    slot.classList.toggle('playable', playable);
    slot.classList.toggle('stackable', stackable);
  }
  $('hand').classList.toggle('my-turn', myTurn);
  $('pass-btn').hidden = !(myTurn && state.canPass);
}

/* ---------- targeted renderers ---------- */
function render(){
  const relight = dirty.pile || dirty.hand || dirty.turn;
  if (dirty.lobby){ renderLobby(); dirty.lobby = false; }
  if (!state.inGame){ dirty.seats = dirty.pile = dirty.hand = dirty.turn = false; return; }
  if (dirty.seats){ renderSeats(); dirty.seats = false; }
  if (dirty.pile){ renderPile(); dirty.pile = false; }
  if (dirty.hand){ renderHand(); dirty.hand = false; }
  if (dirty.turn){ $('turn-banner').hidden = state.current !== name; dirty.turn = false; }
  if (relight) updateHighlights();
}

function renderLobby(){
  const lp = $('lobby-players'); lp.innerHTML = '';
  for (const p of state.players){
    const li = document.createElement('li');
    li.textContent = p === name ? p + ' (you)' : p;
    lp.append(li);
  }
}

function seatOf(player){
  return document.querySelector('.seat[data-player="' + (CSS && CSS.escape ? CSS.escape(player) : player) + '"]');
}

function layoutSeats(){
  const i0 = state.players.indexOf(name);
  const opp = i0 < 0 ? state.players.slice()
    : state.players.slice(i0 + 1).concat(state.players.slice(0, i0));
  const seatsEl = $('seats');
  seatsEl.dataset.opponents = opp.join(' ');
  const k = opp.length, cx = 50, cy = 54, rx = 44, ry = 40;
  opp.forEach((p, j) => {
    const t = (j + 1) / (k + 1);
    const th = (165 - 150 * t) * Math.PI / 180;
    const s = seatOf(p);
    if (!s) return;
    s.style.left = (cx + rx * Math.cos(th)) + '%';
    s.style.top = (cy - ry * Math.sin(th)) + '%';
  });
}

function renderSeats(){
  const i0 = state.players.indexOf(name);
  const opp = i0 < 0 ? state.players.slice()
    : state.players.slice(i0 + 1).concat(state.players.slice(0, i0));
  const seatsEl = $('seats');
  seatsEl.innerHTML = '';
  for (const p of opp){
    const s = document.createElement('div');
    s.className = 'seat' + (p === state.current ? ' turn' : '');
    s.dataset.player = p;
    const fan = document.createElement('div'); fan.className = 'fan';
    const n = state.counts[p];
    const shown = Math.min(n === undefined ? 7 : n, 10);
    for (let i = 0; i < shown; i++){
      const b = cardBackEl(true);
      const mid = (shown - 1) / 2;
      b.style.transform = 'rotate(' + ((i - mid) * 7) + 'deg)' +
                          ' translateY(' + (Math.abs(i - mid) * 2.5) + 'px)';
      fan.append(b);
    }
    const plate = document.createElement('div'); plate.className = 'plate';
    plate.textContent = p;
    if (n !== undefined){
      const b = document.createElement('span');
      b.className = 'count' + (n === 1 ? ' uno' : '');
      b.textContent = n === 1 ? 'UNO!' : n;
      plate.append(b);
    }
    s.append(fan, plate);
    seatsEl.append(s);
  }
  layoutSeats();
}

let lastPileColor = null, lastPileTopId = null;
function renderPile(){
  const d = $('discard');
  d.innerHTML = '';
  // the color can change while the same card stays on top (custom rules):
  // the top card always wears the active color, so re-dress it here
  const top = state.pileStack[state.pileStack.length - 1];
  if (top){
    if (state.color && state.color !== 'NoColor' && top.color !== state.color)
      top.declared = state.color;
    else delete top.declared;
  }
  for (const c of state.pileStack){
    const el = cardEl(c);
    el.style.setProperty('--tilt', tiltOf(c.id) + 'deg');
    d.append(el);
  }
  d.style.setProperty('--cur', COLOR_CSS[state.color] || '#333');
  // pop the pile when the color was CHANGED rather than followed - a wild,
  // a recoloring rule, or a mid-turn recolor with the same card on top.
  // Ordinary plays (printed color, new card) stay quiet.
  const recolored = lastPileColor && lastPileColor !== state.color &&
    top && (top.declared || top.id === lastPileTopId);
  if (recolored && !snapshotMode){
    d.classList.remove('color-pop');
    void d.offsetWidth; // restart the animation
    d.classList.add('color-pop');
  }
  lastPileColor = state.color;
  lastPileTopId = top ? top.id : null;
  const badge = $('pending-badge');
  badge.hidden = !(state.pending > 0);
  badge.textContent = '+' + state.pending;
}

/* ---------- drag to rearrange your hand ---------- */
// the display order belongs to the player: server hand updates are re-sorted
// to match it, and never-seen cards (fresh draws) go on the right
let handOrder = [];
function orderedHand(hand){
  const pos = new Map(handOrder.map((id, i) => [id, i]));
  const known = hand.filter(c => pos.has(c.id))
    .sort((a, b) => pos.get(a.id) - pos.get(b.id));
  const out = known.concat(hand.filter(c => !pos.has(c.id)));
  handOrder = out.map(c => c.id);
  return out;
}

let drag = null; // {slot, startX, startY, moved}

function dragStart(e, slot){
  if (drag || !e.isPrimary || e.button > 0) return;
  drag = { slot, startX: e.clientX, startY: e.clientY, moved: false };
  e.currentTarget.setPointerCapture(e.pointerId);
}
function dragMove(e){
  if (!drag) return;
  let dx = e.clientX - drag.startX;
  if (!drag.moved){
    if (Math.abs(dx) < 8) return; // a click, not a drag (yet)
    drag.moved = true;
    e.currentTarget._dragged = true; // the ending click must not play
    drag.slot.classList.add('dragging');
  }
  const handEl = $('hand');
  const others = [...handEl.children].filter(s => s !== drag.slot);
  // slide the slot to wherever the pointer sits among the other cards
  let target = others.length;
  for (let i = 0; i < others.length; i++){
    const r = rect(others[i]);
    if (e.clientX < r.left + r.width / 2){ target = i; break; }
  }
  if ([...handEl.children].indexOf(drag.slot) !== target){
    const before = new Map(others.map(s => [s.dataset.cid, rect(s).left]));
    const x0 = rect(drag.slot).left;
    handEl.insertBefore(drag.slot, others[target] || null);
    setFan();
    drag.startX += rect(drag.slot).left - x0; // keep the card under the pointer
    dx = e.clientX - drag.startX;
    for (const s of others){
      const d = before.get(s.dataset.cid) - rect(s).left;
      if (Math.abs(d) > 1)
        s.animate([{transform:'translateX(' + d + 'px)'}, {transform:'none'}],
                  {duration:130, easing:'ease-out'});
    }
  }
  const card = drag.slot.firstChild;
  card.style.setProperty('--dx', dx + 'px');
  card.style.setProperty('--dy', (e.clientY - drag.startY) + 'px');
}
// drop (or a mid-drag hand rebuild): commit the DOM order as the new one
function settleDrag(){
  if (!drag) return;
  const { slot, moved } = drag;
  drag = null;
  if (!moved) return;
  slot.classList.remove('dragging');
  slot.firstChild.style.removeProperty('--dx');
  slot.firstChild.style.removeProperty('--dy');
  handOrder = [...$('hand').children].map(s => Number(s.dataset.cid));
  state.hand = orderedHand(state.hand);
  setFan();
}

function makeSlot(card){
  const slot = document.createElement('div');
  slot.className = 'slot';
  slot.dataset.cid = card.id;
  const el = cardEl(card);
  el.onclick = () => {
    if (el._dragged){ el._dragged = false; return; }
    playCard(card);
  };
  el.onpointerdown = e => dragStart(e, slot);
  el.onpointermove = dragMove;
  el.onpointerup = settleDrag;
  el.onpointercancel = settleDrag;
  slot.append(el);
  return slot;
}

function renderHand(){
  settleDrag(); // a mid-drag rebuild keeps whatever order the drag reached
  const handEl = $('hand');
  const have = new Map([...handEl.children].map(s => [s.dataset.cid, s]));
  const before = new Map();
  for (const [id, s] of have) before.set(id, rect(s));
  for (const c of state.hand){
    const s = have.get(String(c.id));
    handEl.append(s || makeSlot(c));
  }
  for (const [id, s] of have)
    if (!state.hand.some(c => String(c.id) === id)) s.remove();
  setFan();
  if (reducedMotion || snapshotMode) return;
  for (const s of handEl.children){
    const r0 = before.get(s.dataset.cid);
    if (!r0) continue;
    const dx = r0.left - rect(s).left;
    if (Math.abs(dx) > 1)
      s.animate([{transform:'translateX(' + dx + 'px)'}, {transform:'none'}],
                {duration:250, easing:'ease-out'});
  }
}

function setFan(){
  const handEl = $('hand');
  const slots = [...handEl.children];
  const n = slots.length;
  if (!n) return;
  const cw = rect(slots[0]).width || 70;
  const avail = Math.min(window.innerWidth - 200, 760);
  const ov = n > 1 ? Math.max(cw * .25, (n * cw - avail) / (n - 1)) : 0;
  handEl.style.setProperty('--overlap', Math.min(ov, cw * .75) + 'px');
  const mid = (n - 1) / 2;
  const spread = Math.min(36, n * 5);
  slots.forEach((slot, i) => {
    const off = mid ? (i - mid) / mid : 0;
    slot.firstChild.style.setProperty('--rot', (off * spread / 2) + 'deg');
    slot.firstChild.style.setProperty('--ty', (off * off * 14) + 'px');
  });
}

/* ---------- flight animations ---------- */
function flyClone(node, from, to, opts = {}){
  node.classList.add('flying');
  node.style.left = from.left + 'px';
  node.style.top = from.top + 'px';
  node.style.setProperty('--card-w', from.width + 'px');
  document.body.append(node);
  const dx = to.left + to.width/2 - (from.left + from.width/2);
  const dy = to.top + to.height/2 - (from.top + from.height/2);
  const sc = to.width / Math.max(from.width, 1);
  const anim = node.animate(
    [{transform:'translate(0,0) scale(1)'},
     {transform:'translate(' + dx + 'px,' + dy + 'px) scale(' + sc + ')'}],
    {duration:opts.dur || 430, easing:'cubic-bezier(.3,.7,.2,1)',
     delay:opts.delay || 0, fill:'both'});
  anim.finished.then(() => { node.remove(); if (opts.onDone) opts.onDone(); })
      .catch(() => node.remove());
}

function runFx(fx){
  // a +2/+4 victim is skipped by the same play; the DRAW splash already
  // says so, so drop their separate skip signal
  const penalized = new Set(fx.filter(f => f.kind === 'penalty').map(f => f.player));
  let splashes = 0;
  const stagger = () => 300 * splashes++;
  for (const f of fx){
    if (f.kind === 'skipped' && !penalized.has(f.player)){
      if (f.player === name) bigSplash('⊘', 'SKIPPED!', 'red', stagger());
      else seatBadge(f.player, '⊘ skipped', 'skip');
    } else if (f.kind === 'penalty'){
      if (f.player === name) bigSplash('+' + f.count, 'DRAW ' + f.count + '!', 'red', stagger());
      else seatBadge(f.player, '+' + f.count + ' cards', 'penalty');
    } else if (f.kind === 'reversed'){
      bigSplash('⇄', 'REVERSED', 'blue mid spin', stagger());
    }
  }
  for (const f of fx){
    if (f.kind === 'ownPlay' || f.kind === 'oppPlay'){
      const top = $('discard').lastElementChild;
      if (!top) continue;
      const el = cardEl(f.card);
      el.style.setProperty('--tilt', tiltOf(f.card.id) + 'deg');
      top.style.visibility = 'hidden';
      flyClone(el, f.from || rect($('draw-pile')), rect($('discard')),
               {onDone: () => { top.style.visibility = ''; }});
    } else if (f.kind === 'ownDraw'){
      const slot = document.querySelector('#hand .slot[data-cid="' + f.id + '"]');
      if (!slot) continue;
      slot.firstChild.style.visibility = 'hidden';
      flyClone(cardBackEl(), f.from, rect(slot),
               {delay:f.delay, onDone: () => { slot.firstChild.style.visibility = ''; }});
    } else if (f.kind === 'oppDraw'){
      const s = seatOf(f.player);
      if (!s) continue;
      for (let i = 0; i < Math.min(f.count, 4); i++)
        flyClone(cardBackEl(true), f.from, rect(s), {delay:i*90, dur:380});
    }
  }
}

function processEvents(events){
  if (!events.length) return;
  const still = snapshotMode || reducedMotion || events.some(e => e.type === 'game_started');
  const fx = [];
  for (const ev of events) apply(ev, still ? null : fx);
  render();
  if (!still) runFx(fx);
}

/* ---------- actions ---------- */
async function playCard(card){
  if (card.value === 'Wild' || card.value === 'Wild4'){
    pendingWild = card;
    $('color-modal').hidden = false;
    return;
  }
  const r = await api('/api/play?card_id=' + card.id, {method:'POST'});
  if (!r.ok) toast(r.error); else lastPlayedId = card.id;
}

document.querySelectorAll('#color-modal .wheel button').forEach(b => {
  b.onclick = async (e) => {
    e.stopPropagation();
    $('color-modal').hidden = true;
    if (!pendingWild) return;
    const id = pendingWild.id; pendingWild = null;
    const r = await api('/api/play?card_id=' + id + '&color=' + b.dataset.color, {method:'POST'});
    if (!r.ok) toast(r.error); else lastPlayedId = id;
  };
});
$('color-modal').onclick = (e) => {
  if (e.target === $('color-modal')){ $('color-modal').hidden = true; pendingWild = null; }
};

$('draw-pile').onclick = async () => {
  const r = await api('/api/draw', {method:'POST'}); if (!r.ok) toast(r.error);
};
$('pass-btn').onclick = async () => {
  const r = await api('/api/pass', {method:'POST'}); if (!r.ok) toast(r.error);
};
$('start-btn').onclick = async () => {
  const r = await api('/api/start', {method:'POST'}); if (!r.ok) toast(r.error);
};
$('win-back').onclick = () => { $('win-overlay').hidden = true; setView('lobby'); };

/* ---------- leaving the party ---------- */
// tells the server we're gone (mid-game a bot takes over; in the lobby the
// seat frees up) and resets this tab back to the join screen
async function leaveParty(){
  try { await api('/api/leave', {method:'POST'}); } catch (e){ /* leaving anyway */ }
  if (polling){ clearInterval(polling); polling = null; }
  sessionStorage.removeItem('uno-name');
  sessionStorage.removeItem('uno-code');
  name = null; code = null;
  state = freshState();
  pendingWild = null; lastPlayedId = null; handOrder = [];
  hideCountdown();
  $('win-overlay').hidden = true;
  $('color-modal').hidden = true;
  $('join-err').textContent = '';
  $('lobby-status').textContent = '';
  setView('join');
}
$('leave-lobby').onclick = leaveParty;
$('leave-game').onclick = () => {
  if (confirm('Leave the game? A bot will take over your hand.')) leaveParty();
};
$('rules-btn').onclick = async () => {
  const r = await api('/api/rules', {method:'POST', body: $('rules-text').value});
  const s = $('rules-status');
  if (r.ok){ s.textContent = 'Rules accepted'; s.className = 'ok'; }
  else { s.textContent = r.error; s.className = 'err'; }
};

/* ---------- rules editor helpers ---------- */
let lastLoaded = '';
let checkT = null;

async function checkRules(){
  const text = $('rules-text').value;
  const st = $('check-status');
  if (!text.trim()){ st.textContent = ''; return; }
  try {
    const r = await api('/api/check-rules', {method:'POST', body:text});
    if (r.ok){
      const warns = r.warnings || [];
      st.textContent = '✓ ' + r.num_rules + ' rules ready';
      st.className = warns.length ? 'warn' : 'ok';
      const FIXES = {missing_play: 'play the card', missing_advance: 'advance turn'};
      for (const w of warns){
        const line = document.createElement('div');
        line.textContent = '⚠ ' + w.message;
        if (FIXES[w.kind]){
          const b = document.createElement('button');
          b.className = 'small';
          b.textContent = 'add ‘' + FIXES[w.kind] + '’';
          b.onclick = () => applyFix(w);
          line.append(b);
        }
        st.append(line);
      }
    }
    else { st.textContent = '✗ ' + r.error; st.className = 'err'; }
  } catch (e){ st.textContent = ''; }
}
function scheduleCheck(){ clearTimeout(checkT); checkT = setTimeout(checkRules, 600); }
$('rules-text').addEventListener('input', scheduleCheck);

/* one-click warning fix: splice the missing effect into the named rule's
   "do" line. 'play the card' goes first (like every built-in), 'advance
   turn' goes last. Duplicate names: the LAST definition is the live one. */
function applyFix(w){
  const ta = $('rules-text');
  const src = ta.value;
  const headRe = new RegExp('rule\\s*"' +
    w.rule.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '"', 'gi');
  let head = null, m;
  while ((m = headRe.exec(src))) head = m;
  const doMatch = head && /\bdo\b[ \t]*/.exec(src.slice(head.index));
  if (!doMatch){ toast('could not find that rule anymore - re-checking'); checkRules(); return; }
  if (w.kind === 'missing_play'){
    const at = head.index + doMatch.index + doMatch[0].length;
    ta.value = src.slice(0, at) + 'play the card, ' + src.slice(at);
  } else {
    const lineEnd = src.indexOf('\n', head.index + doMatch.index);
    const at = lineEnd === -1 ? src.length : lineEnd;
    ta.value = src.slice(0, at).replace(/[ \t]+$/, '') + ', advance turn' + src.slice(at);
  }
  checkRules();
}

// the toggles compose: stacking and draw-until can be on together
function setPreset(stacking, drawuntil){
  const ta = $('rules-text');
  if (ta.value.trim() !== lastLoaded.trim() &&
      !confirm('Replace the current rule text?')) return;
  $('toggle-stacking').classList.toggle('active', stacking);
  $('toggle-drawuntil').classList.toggle('active', drawuntil);
  ta.value = presetText();
  lastLoaded = ta.value;
  checkRules();
  loadOverrideList();
}
const toggleOn = id => $(id).classList.contains('active');
$('preset-standard').onclick = () => setPreset(false, false);
$('toggle-stacking').onclick = () =>
  setPreset(!toggleOn('toggle-stacking'), toggleOn('toggle-drawuntil'));
$('toggle-drawuntil').onclick = () =>
  setPreset(toggleOn('toggle-stacking'), !toggleOn('toggle-drawuntil'));

document.querySelectorAll('.cheat code').forEach(c => c.onclick = () => {
  const ta = $('rules-text');
  ta.setRangeText(c.textContent, ta.selectionStart, ta.selectionEnd, 'end');
  ta.focus();
  scheduleCheck();
});

/* the current preset's rules, offered for copy-and-customize: clicking one
   appends its full text, and the same name makes the copy replace the
   built-in when the ruleset is parsed */
async function loadOverrideList(){
  const box = $('override-list');
  try {
    const r = await api('/api/preset-rules?name=' + encodeURIComponent(presetName()));
    if (!r.ok) return;
    box.innerHTML = '';
    for (const raw of r.text.split(/\n\s*\n/)){
      const block = raw.trim();
      const m = block.match(/^rule "([^"]+)"/);
      if (!m) continue;
      const c = document.createElement('code');
      c.textContent = m[1];
      c.title = block;
      c.onclick = () => {
        const ta = $('rules-text');
        ta.value = ta.value.replace(/\s*$/, '\n\n') +
          '# your version of "' + m[1] + '" - it replaces the built-in rule\n' +
          block + '\n';
        ta.scrollTop = ta.scrollHeight;
        checkRules();
      };
      box.append(c);
    }
  } catch (e){ /* lobby page not connected yet; retried on preset change */ }
}
loadOverrideList();

/* rule builder: conditions and effects both stack as removable chips,
   all joined by clicks, with a live preview of the rule being composed */
let builderConds = ['your turn'];   // the usual guard, removable like any chip
let builderEffs = [];
let customRuleN = 0;

function fillSelect(sel, options){
  options.forEach(([, label], i) => {
    const o = document.createElement('option');
    o.value = i; o.textContent = label;
    sel.append(o);
  });
}
fillSelect($('b-when'), WHEN_OPTIONS);
fillSelect($('b-eff'), EFF_OPTIONS);

function syncBuilderInputs(){
  $('b-when-n').hidden = !WHEN_OPTIONS[$('b-when').value][0].includes('N');
  const eff = EFF_OPTIONS[$('b-eff').value][0];
  $('b-eff-n').hidden = !eff.includes('N');
  $('b-eff-color').hidden = !eff.includes('C');
}
$('b-when').onchange = syncBuilderInputs;
$('b-eff').onchange = syncBuilderInputs;
syncBuilderInputs();

function builderName(){
  return $('b-name').value.trim() || 'my rule ' + (customRuleN + 1);
}
function builderText(){
  const cond = builderConds.length ? builderConds.join(' and ') : 'always';
  return 'rule "' + builderName() + '" priority ' + $('b-prio').value + ':\n' +
         '  when ' + cond + '\n' +
         '  do ' + (builderEffs.join(', ') || '(add at least one effect)') + '\n';
}
function renderChipList(box, arr){
  box.innerHTML = '';
  arr.forEach((t, i) => {
    const s = document.createElement('span');
    s.textContent = t;
    s.title = 'remove';
    s.onclick = () => { arr.splice(i, 1); renderChips(); };
    box.append(s);
  });
}
function renderChips(){
  renderChipList($('b-conds'), builderConds);
  renderChipList($('b-effs'), builderEffs);
  // preview only once the rule differs from the untouched default
  $('b-preview').textContent =
    (builderEffs.length || builderConds.join() !== 'your turn' ||
     $('b-name').value.trim()) ? builderText() : '';
}
// a positive card-play condition means this rule will WIN the card click,
// so it must handle the whole play - pre-add the usual effects (once per
// composition, only into an empty effect list; all removable like any chip)
let autoFilled = false;
function isCardCond(t){
  return !t.startsWith('not ') &&
    (t.startsWith('card ') || t.startsWith('(card ') || t === 'continues stack');
}
$('b-add-cond').onclick = () => {
  let t = WHEN_OPTIONS[$('b-when').value][0].replace('N', $('b-when-n').value || '0');
  if (t.includes(' or ')) t = '(' + t + ')';
  if ($('b-not').checked) t = 'not ' + t;
  $('b-not').checked = false;
  if (!builderConds.includes(t)) builderConds.push(t);
  if (!autoFilled && !builderEffs.length && isCardCond(t)){
    autoFilled = true;
    // mid-stack plays keep the turn, so no advance for "continues stack"
    builderEffs = t === 'continues stack'
      ? ['play the card', 'set color from card']
      : ['play the card', 'set color from card', 'advance turn'];
    toast('Added the usual play effects - remove any chip you don’t want');
  }
  renderChips();
};
// 'advance turn' / 'skip next player' end the turn, so keep exactly one of
// them at the tail: other effects slot in before it, a second one replaces it
const TURN_END = new Set(['advance turn', 'skip next player']);
$('b-add-eff').onclick = () => {
  let t = EFF_OPTIONS[$('b-eff').value][0];
  t = t.replace('N', $('b-eff-n').value || '1').replace('C', $('b-eff-color').value);
  const last = builderEffs[builderEffs.length - 1];
  if (TURN_END.has(t) && TURN_END.has(last)) builderEffs[builderEffs.length - 1] = t;
  else if (TURN_END.has(last) && !TURN_END.has(t))
    builderEffs.splice(builderEffs.length - 1, 0, t);
  else builderEffs.push(t);
  renderChips();
};
$('b-prio').onchange = renderChips;
$('b-name').addEventListener('input', renderChips);
$('b-append').onclick = () => {
  if (!builderEffs.length){ toast('Add at least one effect first'); return; }
  const text = builderText();
  if ($('b-name').value.trim() === '') customRuleN++;
  const ta = $('rules-text');
  ta.value = ta.value.replace(/\s*$/, '\n\n') + text;
  ta.scrollTop = ta.scrollHeight;
  builderConds = ['your turn']; builderEffs = []; autoFilled = false;
  $('b-name').value = '';
  renderChips();
  checkRules();
};
renderChips();

/* ---------- join / snapshot / polling ---------- */
async function refreshState(){
  const r = await api('/api/state');
  if (r.ok){ snapshotMode = true; processEvents(r.events); snapshotMode = false; }
}

async function joinAs(v){
  name = v;
  try {
    const r = await api('/api/join', {method:'POST'});
    if (!r.ok){
      $('join-err').textContent = r.error;
      name = null;
      sessionStorage.removeItem('uno-name');
      sessionStorage.removeItem('uno-code');
      return;
    }
    sessionStorage.setItem('uno-name', v);
    sessionStorage.setItem('uno-code', code);
    $('room-code').textContent = code;
    $('game-code').textContent = 'ROOM ' + code;
    setView('lobby');
    await refreshState();
    startPolling();
  } catch (e){ $('join-err').textContent = 'server unreachable'; name = null; }
}

async function hostGame(){
  const v = $('name-input').value.trim();
  if (!v){ $('join-err').textContent = 'enter your name first'; return; }
  try {
    const res = await fetch('/api/create-room', {method:'POST'});
    const r = await res.json();
    if (!r.ok){ $('join-err').textContent = r.error; return; }
    code = r.code;
    joinAs(v);
  } catch (e){ $('join-err').textContent = 'server unreachable'; }
}

$('host-btn').onclick = hostGame;
$('join-btn').onclick = () => {
  const v = $('name-input').value.trim();
  const c = $('code-input').value.trim().toUpperCase();
  if (!v){ $('join-err').textContent = 'enter your name first'; return; }
  if (c.length !== 4){ $('join-err').textContent = 'room codes are 4 letters'; return; }
  code = c;
  joinAs(v);
};
$('name-input').addEventListener('keydown', e => { if (e.key === 'Enter') $('join-btn').click(); });
$('code-input').addEventListener('keydown', e => { if (e.key === 'Enter') $('join-btn').click(); });

$('copy-link').onclick = async () => {
  const link = location.origin + '/?code=' + code;
  try {
    await navigator.clipboard.writeText(link);
    $('copy-done').textContent = 'copied!';
  } catch (e){ prompt('Copy this link:', link); }
  setTimeout(() => { $('copy-done').textContent = ''; }, 1600);
};

let polling = null;
function startPolling(){
  if (polling) return;
  polling = setInterval(async () => {
    try {
      const r = await api('/api/poll');
      if (r.ok) processEvents(r.events);
    } catch (e){ /* transient */ }
  }, 700);
}

// tell the server we're gone the instant the tab closes, so a bot can take
// over immediately instead of waiting for the poll-silence timeout. sendBeacon
// survives page unload where a normal fetch would be cancelled.
window.addEventListener('pagehide', () => {
  if (name && code)
    navigator.sendBeacon(
      '/api/leave?name=' + encodeURIComponent(name) + '&code=' + encodeURIComponent(code));
});

let resizeT = null;
window.addEventListener('resize', () => {
  clearTimeout(resizeT);
  resizeT = setTimeout(() => { setFan(); layoutSeats(); }, 120);
});

// the draw pile is three static card backs (the badge span stays on top)
for (let i = 0; i < 3; i++)
  $('draw-pile').insertBefore(cardBackEl(), $('pending-badge'));

$('rules-text').value = presetText();
lastLoaded = $('rules-text').value;
checkRules();

// invite links carry ?code=XXXX; a saved session (per-tab) wins unless the
// link points at a different room
const urlCode = (new URLSearchParams(location.search).get('code') || '').toUpperCase();
const savedName = sessionStorage.getItem('uno-name');
const savedCode = sessionStorage.getItem('uno-code');
if (savedName && savedCode && (!urlCode || urlCode === savedCode)){
  $('name-input').value = savedName;
  code = savedCode;
  joinAs(savedName);
} else if (urlCode){
  $('code-input').value = urlCode;
  $('name-input').focus();
}
</script>
</body>
</html>
|html}
;;

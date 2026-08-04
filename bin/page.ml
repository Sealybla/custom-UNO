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
  /* the editor has drifted from what the server was actually sent */
  #rules-btn.needs-apply { background:var(--c-yellow); color:var(--ink);
    animation:pulse 1.2s ease-in-out infinite; }
  ul#lobby-players { list-style:none; padding:0; margin:.2rem 0 1rem; display:flex;
    flex-wrap:wrap; gap:.5rem; }
  ul#lobby-players li.ready { box-shadow:0 0 0 2.5px var(--c-green); }
  ul#lobby-players li .tag { margin-left:.45rem; font-size:.78rem; opacity:.7; }
  ul#lobby-players li.ready .tag { color:#8fe3a8; opacity:1; }
  ul#lobby-players li .crown { position:absolute; top:-1.15em; left:50%;
    transform:translateX(-50%) rotate(-14deg); font-size:1.05em;
    filter:drop-shadow(0 2px 2px rgba(0,0,0,.4)); }
  #ready-btn.active { background:var(--c-green); color:#fff; }
  button:disabled { opacity:.45; cursor:not-allowed; }
  ul#lobby-players li { background:rgba(255,255,255,.14); border-radius:999px;
    padding:.35rem .9rem; font-weight:700; position:relative; margin-top:.9em; }
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
  #b-turn-hint { color:#ffd97a; font-size:.78rem; margin:.15rem 0 .3rem; }
  .set-lbl { font-size:.85rem; display:inline-flex; gap:.35rem; align-items:center; }
  #table-settings input[type=number] { width:4.6rem; border-radius:8px;
    padding:.3rem .45rem; font-size:.88rem; }
  .cheat-note { opacity:.7; font-size:.78rem; margin:.1rem 0 .3rem; }
  #recipes-head { margin:.7rem 0 0; font-size:.78rem; text-transform:uppercase;
    letter-spacing:.08em; opacity:.7; }
  #recipes { display:grid; grid-template-columns:repeat(auto-fill,minmax(11.5rem,1fr));
    gap:.55rem; margin:.45rem 0 .2rem; }
  .recipe { border:1px solid rgba(255,255,255,.22); border-radius:12px;
    background:rgba(255,255,255,.06); padding:.55rem .65rem; cursor:pointer;
    display:flex; gap:.55rem; align-items:flex-start;
    transition:border-color .15s, background .15s; }
  .recipe:hover { border-color:rgba(255,206,0,.6); }
  .recipe.on { border-color:var(--c-yellow); background:rgba(255,206,0,.13); }
  .recipe .r-mini { flex:0 0 1.5rem; height:2.1rem; border-radius:5px; position:relative;
    box-shadow:0 2px 4px rgba(0,0,0,.4); }
  .recipe .r-mini::after { content:attr(data-g); position:absolute; inset:0;
    display:grid; place-items:center; color:#fff; font-weight:800; font-size:.72rem;
    text-shadow:0 1px 2px rgba(0,0,0,.5); }
  .recipe .r-t { font-weight:650; font-size:.82rem; line-height:1.25; display:block; }
  .recipe.on .r-t::after { content:" ✓"; color:var(--c-yellow); }
  .recipe .r-d { opacity:.72; font-size:.74rem; line-height:1.3; margin-top:.15rem; display:block; }
  .recipe input { width:3rem; margin:0 .15rem; border-radius:6px; border:none;
    padding:.1rem .3rem; font-size:.74rem; }
  .r-red { background:var(--c-red); } .r-blue { background:var(--c-blue); }
  .r-green { background:var(--c-green); } .r-yellow { background:#d4a900; }
  #custom-rules > summary { cursor:pointer; font-size:.95rem; margin:.9rem 0 .3rem;
    user-select:none; opacity:.9; }
  /* smart editor: a colored copy of the text sits behind a transparent
     textarea, so both must share every metric that affects layout */
  #ed-wrap { position:relative; }
  #ed-wrap textarea, #hl, #ed-mirror { font-family:ui-monospace,monospace;
    font-size:.85rem; line-height:1.5; padding:.5rem .6rem; margin:0;
    box-sizing:border-box; width:100%; white-space:pre-wrap; overflow-wrap:break-word; }
  #hl, #ed-mirror { position:absolute; inset:0; overflow:hidden;
    border:1px solid transparent; pointer-events:none; }
  #hl { background:#140c0c; color:#ffe9c9; }
  #ed-mirror { visibility:hidden; }
  #ed-wrap textarea { position:relative; display:block; background:transparent;
    color:transparent; caret-color:#ffe9c9; resize:vertical; }
  .e-kw { color:#ffce00; font-weight:600; } .e-cond { color:#7cc7ff; }
  .e-eff { color:#8fe3a8; } .e-str { color:#ffb0b0; } .e-num { color:#ffd97a; }
  .e-cm { opacity:.55; }
  #ac-pop { position:absolute; z-index:5; background:#2c1b18;
    border:1px solid rgba(255,206,0,.5); border-radius:8px; overflow:hidden;
    box-shadow:0 6px 18px rgba(0,0,0,.5); font-size:.78rem; max-width:26rem; }
  #ac-pop div { padding:.3rem .7rem; cursor:pointer; white-space:nowrap;
    overflow:hidden; text-overflow:ellipsis; }
  #ac-pop div.sel { background:rgba(255,206,0,.2); }
  #ac-pop b { font-family:ui-monospace,monospace; font-weight:600; }
  #ac-pop small { opacity:.65; margin-left:.6rem; }
  #phrase-help { min-height:1.1rem; font-size:.76rem; opacity:.85;
    margin:.25rem 0 0; font-family:ui-monospace,monospace; }
  #phrase-help b { color:var(--c-yellow); }
  #check-status button { margin-left:.5rem; padding:.05rem .5rem; font-size:.72rem; }
  #override-list { display:flex; flex-wrap:wrap; gap:.35rem; margin-top:.5rem; font-size:.83rem; }
  #override-list code { cursor:pointer; padding:.14rem .45rem; border-radius:6px;
    background:rgba(255,255,255,.1); }
  #override-list code:hover { background:rgba(255,206,0,.35); }
  .mode-del { padding:.1rem .45rem; margin-left:-.35rem; opacity:.7; }
  .mode-del:hover { opacity:1; background:var(--c-red); color:#fff; }
  #login-user, #login-pw { border-radius:8px; padding:.4rem .6rem; width:9.5rem; }
  .panel details { margin:.7rem 0 0; background:rgba(0,0,0,.28); border-radius:12px;
    padding:.55rem .9rem; }
  .panel summary { cursor:pointer; font-weight:800; }
  .b-row { display:flex; gap:.5rem; align-items:center; flex-wrap:wrap; margin:.6rem 0; }
  .b-row > label:first-child { font-weight:800; font-style:italic; width:3.4rem; }
  .b-row select, .b-row input[type=number], .b-row input[type=text],
  .b-row input:not([type]) { border-radius:8px; padding:.35rem .5rem; font-size:.88rem; }
  .b-row input[type=number] { width:4.2rem; }
  #b-name { flex:1; min-width:8rem; }
  .chips { display:flex; flex-wrap:wrap; gap:.4rem; margin:.2rem 0 .2rem 3.9rem; }
  .chips:empty { display:none; }
  #b-preview { background:rgba(255,255,255,.08); border-radius:8px; padding:.5rem .7rem;
    margin:.5rem 0 0; font-size:.8rem; white-space:pre-wrap; }
  #b-preview:empty { display:none; }
  .chips span { background:var(--c-yellow); color:var(--ink); font-weight:700;
    font-size:.78rem; border-radius:999px; padding:.2rem .6rem; cursor:pointer; }
  .chips span::after { content:' ✕'; opacity:.6; }
  .b-cond-row { display:flex; flex-wrap:wrap; gap:.4rem; align-items:center;
    margin:.25rem 0 .25rem 3.9rem; }
  .b-cond-row .cchip { background:var(--c-yellow); color:var(--ink); font-weight:700;
    font-size:.78rem; border-radius:999px; padding:.2rem .6rem; cursor:pointer; }
  .b-cond-row .cchip.neg { background:var(--ink); color:var(--c-yellow);
    box-shadow:inset 0 0 0 2px var(--c-yellow); }
  .b-cond-row .cchip b { margin-left:.35rem; opacity:.55; font-weight:900; }
  .b-cond-row .cchip b:hover { opacity:1; }
  .b-cond-row .cjoin { font-size:.75rem; font-style:italic; opacity:.75; }
  .b-row-x { opacity:.65; }
  .b-row-x:hover { opacity:1; }
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
  /* of-type, not nth-child: #pending-badge is a <span> sibling in here and
     would otherwise shift every card back by one */
  #draw-pile .card:nth-of-type(1){ transform:translate(-4px,4px) rotate(-4deg); }
  #draw-pile .card:nth-of-type(2){ transform:translate(2px,-1px) rotate(2deg); }
  #draw-pile:hover .card:nth-of-type(3){ transform:translateY(-8px); }
  #draw-pile .card { transition:transform .15s; }
  #discard { border-radius:calc(var(--card-w)*.13);
    box-shadow:0 0 0 5px var(--cur,#333), 0 0 26px var(--cur,transparent);
    transition:box-shadow .35s; }
  #discard .card { transform:rotate(var(--tilt,0deg)); }
  .pile-wrap { display:flex; flex-direction:column; align-items:center; gap:.45rem; }
  .pile-label { font-size:.6rem; font-weight:900; font-style:italic; letter-spacing:.14em;
    text-transform:uppercase; color:rgba(255,255,255,.82); text-shadow:0 1px 2px rgba(0,0,0,.6); }
  #discard.color-pop { animation:colorpop .55s var(--ease-pop); }
  @keyframes colorpop { 35% { transform:scale(1.16); } }
  /* anchors to #draw-pile, which is .pile { position:relative } */
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
  /* deliberately always live, never greyed: pressing it at the wrong moment
     is a real move with a real cost, and dimming it would leak who is
     currently catchable */
  #uno-btn { margin-bottom:calc(var(--card-w)*.4); background:var(--c-yellow);
    color:var(--ink); font-weight:900; font-style:italic; font-size:1.15rem;
    letter-spacing:.06em; padding:.5rem 1.15rem; border:3px solid var(--ink);
    border-radius:999px; box-shadow:0 4px 0 rgba(0,0,0,.45); cursor:pointer;
    transition:transform .12s var(--ease-pop), box-shadow .12s; }
  #uno-btn:hover { transform:translateY(-2px) scale(1.05);
    box-shadow:0 6px 0 rgba(0,0,0,.45); }
  #uno-btn:active { transform:translateY(2px); box-shadow:0 1px 0 rgba(0,0,0,.45); }
  /* flashes for everyone while an UNO catch window is open - a nudge, not a
     disclosure: it never reveals anyone else's hand */
  #uno-btn.armed { animation:unopulse .8s ease-in-out infinite; }
  @keyframes unopulse { 50% { box-shadow:0 4px 0 rgba(0,0,0,.45),
      0 0 22px 6px rgba(255,206,0,.85); } }
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
  #swap-modal { position:fixed; inset:0; background:rgba(0,0,0,.65);
    display:flex; align-items:center; justify-content:center; z-index:30; }
  #swap-modal .swap-box { background:var(--paper); border-radius:16px;
    padding:1rem 1.3rem; min-width:min(320px,80vw);
    box-shadow:0 0 0 6px #fff, 0 20px 60px rgba(0,0,0,.5);
    animation:wheelin .35s var(--ease-pop); transform:none; }
  #swap-modal h3 { margin:.1rem 0 .6rem; }
  #swap-modal .swap-list { display:flex; flex-direction:column; gap:.5rem; }
  #swap-modal .swap-list button { width:100%; text-align:left; }
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

    <div style="margin-top:1.1rem; border-top:2px dashed rgba(255,255,255,.25); padding-top:.8rem">
      <div id="login-form">
        <div style="opacity:.7; font-weight:800; margin:.1rem 0 .5rem">— optional: log in to save custom modes —</div>
        <div style="display:flex; gap:.5rem; justify-content:center; flex-wrap:wrap">
          <input id="login-user" placeholder="username" maxlength="24" autocomplete="username">
          <input id="login-pw" placeholder="password" type="password" maxlength="64" autocomplete="current-password">
          <button id="login-btn" class="small">Log in / sign up</button>
        </div>
      </div>
      <div id="login-info" hidden>
        <span id="login-who" style="font-weight:800"></span>
        <button id="logout-btn" class="small">Log out</button>
      </div>
      <div id="login-err" class="err" style="margin-top:.4rem"></div>
    </div>
  </div>

  <div id="view-lobby" class="lobby-grid" hidden>
    <div class="panel">
      <h2>Lobby <span id="room-code" class="code-chip"></span></h2>
      <p style="margin:.1rem 0 .8rem">
        <button id="copy-link" class="small">Copy invite link</button>
        <span id="copy-done" class="ok"></span>
      </p>
      <ul id="lobby-players"></ul>
      <button id="ready-btn">I'm ready</button>
      <button id="start-btn" disabled>Start game</button>
      <button id="leave-lobby" class="leave">Leave lobby</button>
      <div id="start-hint" style="margin-top:.5rem; font-size:.85rem; opacity:.8"></div>
      <div id="lobby-status" class="ok" style="margin-top:.3rem"></div>
    </div>
    <div class="panel">
      <h2>House rules</h2>
      <div class="preset-row">
        <span style="opacity:.8">Preset:</span>
        <button class="preset" id="preset-standard">Standard</button>
        <span style="opacity:.8">+ toggles:</span>
        <button class="preset toggle" id="toggle-stacking">Stacking</button>
        <button class="preset toggle" id="toggle-drawuntil">Draw until playable</button>
        <button class="preset toggle" id="toggle-jumpin" title="play out of turn on an exact match">Jump in</button>
        <button class="preset toggle" id="toggle-sevenzero" title="7s swap hands with the next player, 0s send every hand one seat along">7-0</button>
      </div>
      <div class="preset-row" id="table-settings">
        <span style="opacity:.8">Table:</span>
        <label class="set-lbl" title="cards dealt to each player at the start (default 7)">deal
          <input id="set-deal" type="number" min="1" max="30" value="7"> cards</label>
        <label class="set-lbl" title="seconds before the server plays for a stalled player (default 20; 0 = no clock)">turn timer
          <input id="set-timer" type="number" min="0" max="300" step="5" value="20"> s</label>
      </div>
      <div id="recipes-head">House rules — click to add</div>
      <div id="recipes"></div>
      <div id="modes-row" class="preset-row" hidden>
        <span style="opacity:.8">My modes:</span>
        <span id="mode-chips" style="display:contents"></span>
        <input id="mode-name" placeholder="save as…" maxlength="40" style="width:7.5rem">
        <button id="mode-save" class="small">Save current</button>
      </div>

      <details id="custom-rules">
        <summary>✍️ Custom rules — write your own (builder, editor, all phrases)</summary>
      <div id="check-status"></div>
      <div id="ed-wrap">
        <pre id="hl" aria-hidden="true"></pre>
        <textarea id="rules-text" rows="12" spellcheck="false"></textarea>
        <div id="ac-pop" hidden></div>
      </div>
      <div id="phrase-help"></div>

      <details id="builder">
        <summary>🛠 Compose a new rule without typing</summary>
        <div class="b-row"><label>When</label>
          <select id="b-when"></select>
          <input id="b-when-n" type="number" value="0" min="0" hidden>
          <select id="b-when-color" hidden>
            <option>red</option><option>yellow</option>
            <option>green</option><option>blue</option>
          </select>
          <button id="b-add-cond" class="small" title="start a new line — every line must hold">+ and condition</button>
        </div>
        <div id="b-conds"></div>
        <div id="b-turn-hint" hidden>⚠ no “your turn” line — this rule fires for ANY
        player, even when it isn’t their turn (a jump-in rule). Re-add it from the
        condition menu if that’s not what you meant.</div>
        <div class="b-row"><label>Then</label>
          <select id="b-eff"></select>
          <input id="b-eff-n" type="number" value="2" min="1" hidden>
          <select id="b-eff-color" hidden>
            <option>red</option><option>yellow</option>
            <option>green</option><option>blue</option>
          </select>
          <input id="b-eff-msg" placeholder="message to show" maxlength="80" hidden>
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
          <button id="b-clear" class="small" title="throw this rule away and reset the builder">↺ start over</button>
        </div>
        <p style="opacity:.7; font-size:.8rem; margin:.3rem 0 0">Conditions stack as
        lines: every line must hold ("and"), and a line holds if any chip in it does
        (grow a line with its "+ or…" button). Click a chip to flip it to "not", click
        its × to remove it, or drop a whole line with "× line". "↺ start over" resets
        the builder. Picking a card condition pre-adds the usual play effects. The
        pre-added “your turn” line is the turn-order guard — turn order only exists
        because rules demand it.</p>
      </details>

      <details id="override">
        <summary>🔁 Change a built-in rule</summary>
        <p style="opacity:.75; font-size:.82rem; margin:.3rem 0 0">Click a rule to copy it
        into the editor, then tweak its effects. Your copy keeps the same name, so it
        replaces the built-in version.</p>
        <div id="override-list"></div>
      </details>

      <details>
        <summary>📖 All phrases — click to insert at your cursor, hover for what it does</summary>
        <pre class="cheat-shape">rule "name" priority 100:
  when &lt;condition&gt;
  do &lt;effect&gt;, &lt;effect&gt;</pre>
        <div class="cheat">
          <div>
            <h4>Presets</h4>
            <code title="official rules: a +2/+4 makes the next player draw immediately and lose their turn">use standard</code>
            <code title="chain same-value cards in one turn; +2/+4 penalties pile up until someone can't answer">use stacking</code>
            <code title="no passing: draw one card at a time until you can play">use draw until playable</code>
            <code title="both variants combined">use stacking with draw until playable</code>
            <code title="ADD-ON: use it after a base preset — 7s swap hands with the next player, 0s rotate all hands">use seven zero</code>
            <code title="drop a rule pulled in by use — the cards it powered become unplayable. Put it AFTER the use line; a later rule with the same name re-adds it">remove rule "play plus four"</code>
            <h4 style="margin-top:.6rem">Settings</h4>
            <div class="cheat-note">not rules — no when/do, just a line of its own:<br>
            <b>deal</b> &lt;1–30&gt; <b>cards</b> · <b>turn timer</b> &lt;5–300&gt; <b>seconds</b> · <b>turn timer off</b></div>
            <code title="cards dealt to each player at the start (default 7, max 30; the deck must cover every player)">deal 9 cards</code>
            <code title="seconds before the server plays for a stalled player (default 20, range 5-300)">turn timer 15 seconds</code>
            <code title="no clock: turns wait forever">turn timer off</code>
            <h4 style="margin-top:.6rem">Conditions</h4>
            <code title="the played card's printed color equals the color to match">card matches color</code>
            <code title="the played card's value equals the top card's value">card matches value</code>
            <code title="the played card has the same printed color AND number as the top card — the jump-in trigger; wilds never match">card matches exactly</code>
            <code title="the played card is a wild or a +4">card is wild</code>
            <code title="the played card is a skip">card is skip</code>
            <code title="the played card is a reverse">card is reverse</code>
            <code title="the played card is a +2">card is plus two</code>
            <code title="the played card is a +4">card is plus four</code>
            <code title="the played card is that number (any of 0-9 works), whatever its color">card is 7</code>
            <code title="the played card's printed color (wilds have none, so they never match)">card is blue</code>
            <code title="the played card is a skip, reverse, +2, +4 or wild">card is action</code>
            <code title="the played card is any 0-9, whatever its color">card is number</code>
            <code title="the acting player holds exactly this many cards (counted before the card leaves the hand)">hand size = 1</code>
            <code title="the acting player holds more than this many cards">hand size > 6</code>
            <code title="some player OTHER than you holds exactly that many — leader-watch rules">any opponent has 1 card</code>
            <code title="some player other than you holds more than that many">any opponent has more than 10 cards</code>
            <code title="the pile SHOWS this number (whatever you're doing) — different from 'card is 7', which tests the card you're playing">top card is 7</code>
            <code title="the pile shows a skip, reverse, +2, +4 or wild">top card is action</code>
            <code title="play is moving clockwise — write 'direction is counter' for the other way">direction is clockwise</code>
            <code title="the draw pile just ran out (it reshuffles automatically; this fires in the moment)">draw pile is empty</code>
            <code title="the draw pile is running low — endgame rules">draw pile < 10</code>
            <code title="the table's color to match right now — works for any action, not just card plays">active color is red</code>
            <code title="the player clicked draw">player draws</code>
            <code title="the player clicked done">player passes</code>
            <code title="the UNO button was pressed — its own action, never turn-gated">player calls uno</code>
            <code title="the presser is down to exactly one card (their own catch window is open)">has uno</code>
            <code title="some other player sits on one card with their catch window still open">someone has uno</code>
            <code title="the played card has the open stack's value">continues stack</code>
            <code title="someone is mid-chain: a stack is open">stack is open</code>
            <code title="the card just drawn is playable, and the player is deciding to play it or pass">drew playable card</code>
            <code title="stacked +2/+4 penalty cards are waiting to be drawn">pending draws > 0</code>
            <code title="the acting player is the current player — the turn-order guard every normal rule needs">your turn</code>
            <code title="matches any action by anyone — use with care">always</code>
          </div>
          <div>
            <h4>Effects</h4>
            <code title="move the card from the hand onto the pile (winning is checked here)">play the card</code>
            <code title="the played card's printed color becomes the color to match">set color from card</code>
            <code title="the color the player picked becomes the color to match (for wilds)">set color to declared</code>
            <code title="force a specific color to match">set color to red</code>
            <code title="the acting player draws that many cards">draw 2 cards</code>
            <code title="draw 1 card; if it's playable keep the turn open, otherwise the turn ends">draw and decide</code>
            <code title="the next player draws now; whose turn it is doesn't change">next player draws 2 cards</code>
            <code title="grow the stackable +2/+4 penalty instead of drawing now">add 2 pending draws</code>
            <code title="the acting player draws every pending penalty card">apply pending draws</code>
            <code title="draw 1 card and keep the turn; a playable draw is flagged for other rules">draw until playable</code>
            <code title="flip the turn order (with 2 players this skips the opponent instead)">reverse direction</code>
            <code title="the turn jumps over the next player">skip next player</code>
            <code title="stay on turn and chain more cards of this value">open stack</code>
            <code title="end the chain (the done button does this)">close stack</code>
            <code title="the acting player takes the turn — pair with 'not your turn' for out-of-turn plays">jump in</code>
            <code title="a player the actor picks draws that many cards (the UI asks who) — still delivers when it's the winning card">chosen player draws 4 cards</code>
            <code title="the acting player picks any other player and trades entire hands with them (the UI asks who)">swap hands with chosen player</code>
            <code title="the acting player trades entire hands with the next player (in play direction)">swap hands with next player</code>
            <code title="every hand moves one seat in the play direction">rotate hands</code>
            <code title="every player except the actor draws that many cards">everyone else draws 2 cards</code>
            <code title="make the move ILLEGAL: the click is refused and this message is shown — blocking rules like 'no going out on an action card'">reject "not allowed"</code>
            <code title="the presser is safe: closes their own catch window">mark uno called</code>
            <code title="a false UNO call: the presser draws the penalty">penalize caller 2 cards</code>
            <code title="the caught player draws the penalty and their window closes">penalize uncalled player 2 cards</code>
            <code title="end the acting player's turn">advance turn</code>
          </div>
        </div>
        <p style="opacity:.75; font-size:.82rem">Join conditions with <b>and</b> / <b>or</b> / <b>not</b>, parentheses to group. When several rules match, the highest priority wins; on a tie, the rule defined first wins (so built-ins pulled in by <b>use</b> beat same-priority rules below them — replace them by name or use a higher priority).</p>
      </details>
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
    <div class="pile-wrap">
      <div id="draw-pile" class="pile" title="click to draw a card">
        <span id="pending-badge" hidden></span>
      </div>
      <span class="pile-label">Draw Pile</span>
    </div>
    <div class="pile-wrap">
      <div id="discard" class="pile"></div>
      <span class="pile-label">Discard</span>
    </div>
  </div>
  <div id="turn-banner" hidden>YOUR TURN</div>
  <div id="turn-countdown" hidden><span class="num"></span><span class="msg"></span></div>
  <div id="hand-area">
    <div id="hand"></div>
    <button id="pass-btn" hidden>Done</button>
    <button id="uno-btn" title="claim your UNO - or catch someone who forgot">UNO!</button>
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

<div id="swap-modal" hidden>
  <div class="swap-box">
    <h3>Aim it at…</h3>
    <div class="swap-list"></div>
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
const JUMP_IN_DESC =
  'Jump in: when your card is an exact match of the top card you may play it ' +
  'out of turn, skipping everyone between you and the last player.';
const SEVEN_ZERO_DESC =
  'Seven-zero: playing a 7 trades hands with the next player, playing a 0 ' +
  'sends every hand one seat along the play direction.';
// jump-in composes onto any of the four bases, giving the eight preset names
// in lib/presets.ml
function baseName(){
  const s = $('toggle-stacking').classList.contains('active');
  const d = $('toggle-drawuntil').classList.contains('active');
  return s && d ? 'stacking with draw until playable'
       : s ? 'stacking' : d ? 'draw until playable' : 'standard';
}
function jumpInOn(){ return $('toggle-jumpin').classList.contains('active'); }
function sevenZeroOn(){ return $('toggle-sevenzero').classList.contains('active'); }
function presetName(){
  const base = baseName();
  if (!jumpInOn()) return base;
  return base === 'standard' ? 'jump in' : base + ' with jump in';
}
// the Table row's values as directive lines; defaults write nothing, so
// untouched settings never clutter the text
const DEFAULT_DEAL = 7, DEFAULT_TIMER = 20;
function settingsLines(){
  // snap to what the parser accepts (deal 1-30; timer 0=off or 5-300) and
  // show the snapped value, so a typed 3 becomes a working 5 instead of a
  // parse error in the status line
  let d = parseInt($('set-deal').value, 10);
  let t = parseInt($('set-timer').value, 10);
  if (Number.isFinite(d)) $('set-deal').value = d = Math.min(30, Math.max(1, d));
  if (Number.isFinite(t))
    $('set-timer').value = t = t <= 0 ? 0 : Math.min(300, Math.max(5, t));
  return (Number.isFinite(d) && d !== DEFAULT_DEAL ? 'deal ' + d + ' cards\n' : '') +
    (Number.isFinite(t) && t !== DEFAULT_TIMER
      ? (t === 0 ? 'turn timer off\n' : 'turn timer ' + t + ' seconds\n') : '');
}
function presetText(){
  const desc = PRESET_DESC[baseName()] + (jumpInOn() ? '\n# ' + JUMP_IN_DESC : '') +
    (sevenZeroOn() ? '\n# ' + SEVEN_ZERO_DESC : '');
  // seven-zero is an ADD-ON preset: a second `use` line appends its rules
  return '# ' + desc + '\n' +
    'use ' + presetName() + '\n' +
    (sevenZeroOn() ? 'use seven zero\n' : '') +
    settingsLines() + '\n' +
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
  ['card is N', 'a specific number (0-9) is played'],
  ['card is C', 'a card of a specific color is played'],
  ['card is action', 'a skip / reverse / +2 / +4 / wild is played'],
  ['card is number', 'any number card is played'],
  ['player draws', 'the player clicks draw'],
  ['player passes', 'the player clicks done'],
  ['continues stack', 'a card continues the stack'],
  ['stack is open', 'a stack is open'],
  ['drew playable card', 'the drawn card is playable'],
  ['pending draws > N', 'penalty draws are pending'],
  ['hand size = N', 'the acting player holds exactly N cards'],
  ['hand size > N', 'the acting player holds more than N cards'],
  ['any opponent has N cards', 'some other player holds exactly N'],
  ['any opponent has more than N cards', 'some other player holds more than N'],
  ['top card is N', 'the pile shows a specific number (0-9)'],
  ['top card is action', 'the pile shows a skip/reverse/+2/+4/wild'],
  ['direction is clockwise', 'play is moving clockwise'],
  ['draw pile is empty', 'the draw pile just ran out'],
  ['draw pile < N', 'the draw pile is running low'],
  ['card matches exactly', 'same color AND number as the top card'],
  ['player calls uno', 'the UNO button was pressed'],
  ['has uno', 'the presser is down to one card'],
  ['someone has uno', 'someone else is catchable'],
  ['active color is C', 'the color to match is a specific color'],
  ['your turn', 'the acting player is the current player (turn guard)'],
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
  ['jump in', 'take the turn, skipping everyone in between'],
  ['chosen player draws N cards', 'a player you pick draws'],
  ['swap hands with chosen player', 'trade hands with a player you pick'],
  ['swap hands with next player', 'trade hands with the next player'],
  ['rotate hands', 'every hand moves one seat along'],
  ['everyone else draws N cards', 'all other players draw'],
  ['reject "M"', 'block the move (your message is shown to the clicker)'],
  ['mark uno called', 'the presser is safe'],
  ['penalize caller N cards', 'fine the presser'],
  ['penalize uncalled player N cards', 'fine the player who got caught'],
];

let name = null;
let code = null;
const freshState = () => ({ players:[], hand:[], top:null, color:null, current:null,
              counts:{}, inGame:false, pileStack:[], pending:0,
              canPass:false, stackValue:null, stacking:false, unoRace:false,
              // card ids the server says are legal for us right now
              playable:new Set(),
              // subset of playable that needs a swap target picked first
              swapTargets:new Set(),
              ready:[], lastWinner:null });
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
      state.players = ev.players;
      state.ready = ev.ready || [];
      state.lastWinner = ev.last_winner || null;
      dirty.lobby = true;
      if (!state.inGame) setView('lobby');
      break;
    case 'game_started':
      hideCountdown();
      handOrder = [];
      lastPileColor = null; lastPileTopId = null;
      state.inGame = true; state.unoRace = false;
      state.hand = orderedHand(ev.hand); state.top = ev.top_card;
      state.color = ev.current_color; state.players = ev.players;
      state.current = ev.current_player; state.counts = {};
      state.pileStack = [ev.top_card]; state.pending = ev.pending || 0;
      state.stacking = !!ev.stacking; state.canPass = false; state.stackValue = null;
      // a 'hand' event follows immediately with the real set
      state.playable = new Set();
      state.swapTargets = new Set();
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
      state.hand = orderedHand(ev.hand);
      state.playable = new Set(ev.playable || []);
      state.swapTargets = new Set(ev.swap_targets || []);
      // turn too: highlights change without the turn changing when a
      // jump-in becomes available on somebody else's go
      dirty.hand = dirty.turn = true;
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
      // the race is on: someone is sitting on one card and EVERYONE's UNO
      // button is live - save yourself or catch them
      if (ev.uno_race && !state.unoRace) logLine('UNO race - hit the button!');
      state.unoRace = !!ev.uno_race;
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
    case 'uno_penalty':
      logLine((ev.player === name ? 'you' : ev.player) +
              (ev.caught ? ' got caught without calling UNO, +'
                         : ' called UNO for nothing, +') + ev.count);
      if (fx) fx.push({kind:'penalty', player:ev.player, count:ev.count});
      break;
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
    case 'hands_moved': {
      // two reciprocal moves are a swap; one per player is a rotate
      const swap = ev.moves.length === 2 &&
        ev.moves[0][0] === ev.moves[1][1] && ev.moves[0][1] === ev.moves[1][0];
      logLine(swap
        ? ev.moves[0][0] + ' and ' + ev.moves[0][1] + ' traded hands'
        : 'every hand moved one seat along');
      if (fx) fx.push({kind:'handsMoved', moves:ev.moves, swap});
      break;
    }
    case 'jumped_in':
      logLine((ev.player === name ? 'you' : ev.player) + ' jumped in!');
      if (fx) fx.push({kind:'jumpin', player:ev.player});
      break;
    case 'game_over':
      state.inGame = false;
      hideCountdown();
      $('lobby-status').textContent = 'Last game: ' + ev.winner + ' won';
      showWin(ev.winner);
      break;
    case 'rules_updated':
      // everyone's editor mirrors the room's accepted rules; an empty
      // player marks a state snapshot rather than a fresh edit
      if (ev.rules_text){
        // this text IS what the server accepted, so it also settles the
        // "editor has unsent changes" nag for everyone in the room
        appliedText = ev.rules_text;
        if (ev.rules_text !== $('rules-text').value){
          $('rules-text').value = ev.rules_text;
          lastLoaded = ev.rules_text;
          scheduleCheck();
        }
        markRulesDirty();
      }
      if (ev.player){
        $('rules-status').textContent = ev.player + ' set ' + ev.num_rules + ' house rules';
        $('rules-status').className = 'ok';
        logLine(ev.player + ' updated the rules');
        if (ev.player !== name) toast(ev.player + ' updated the rules');
      }
      break;
    case 'rejected': toast(ev.reason); break;
  }
}

/* ---------- playable / stackable helpers ---------- */
const NUMBER_VALUES = new Set(['Zero','One','Two','Three','Four','Five',
                               'Six','Seven','Eight','Nine']);

// Legality comes from the server (Rule_engine.playable_card_ids), which
// simulates each play against the live ruleset. The browser deliberately
// does not reimplement it: house rules can say anything, and an out-of-turn
// jump-in is playable while it is somebody else's turn.
const isPlayable = (card) => state.playable.has(card.id);

// lift + glow every playable card; gold-pulse the ones that can be chained
// as a same-value stack (only meaningful when the ruleset can open stacks)
function updateHighlights(){
  const myTurn = state.inGame && state.current === name;
  const copies = {};
  for (const c of state.hand) copies[c.value] = (copies[c.value] || 0) + 1;
  for (const slot of $('hand').children){
    const card = state.hand.find(c => String(c.id) === slot.dataset.cid);
    const playable = !!(card && isPlayable(card));
    const stackable = playable && state.stacking && NUMBER_VALUES.has(card.value) &&
      (state.stackValue ? true : copies[card.value] > 1);
    slot.classList.toggle('playable', playable);
    slot.classList.toggle('stackable', stackable);
  }
  $('hand').classList.toggle('my-turn', myTurn);
  $('pass-btn').hidden = !(myTurn && state.canPass);
  // only ever keys off your OWN hand, so it cannot tell you when an
  // opponent is catchable - that is the part you are supposed to notice
  // server-driven: flashes for EVERYONE while a catch window is open
  // (save yourself or catch them), stops the moment the race is settled
  $('uno-btn').classList.toggle('armed', state.unoRace);
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
    const rdy = state.ready.includes(p);
    li.classList.toggle('ready', rdy);
    if (p === state.lastWinner){
      const c = document.createElement('span');
      c.className = 'crown'; c.textContent = '👑';
      c.title = 'won the last game';
      li.append(c);
    }
    li.append(document.createTextNode(p === name ? p + ' (you)' : p));
    const tag = document.createElement('span');
    tag.className = 'tag';
    tag.textContent = rdy ? '✔ ready' : '· not ready';
    li.append(tag);
    lp.append(li);
  }
  const meReady = state.ready.includes(name);
  const rb = $('ready-btn');
  rb.textContent = meReady ? 'Not ready' : 'I’m ready';
  rb.classList.toggle('active', meReady);
  const allReady = state.players.length >= 2 &&
    state.players.every(p => state.ready.includes(p));
  $('start-btn').disabled = !allReady;
  const waiting = state.players.filter(p => !state.ready.includes(p));
  $('start-hint').textContent =
    state.players.length < 2 ? 'Waiting for more players to join…'
    : allReady ? 'Everyone is ready - anyone can start the game!'
    : 'Waiting for: ' + waiting.join(', ');
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
  // give the draw pile a visible face-down stack (3 backs = what the CSS
  // nth-child rules style). Build once; rebuilding each pile update would
  // interrupt the hover-lift animation. NOTE: test for card children, not
  // any children - #pending-badge lives in here too and is always present.
  const dp = $('draw-pile');
  if (!dp.querySelector('.card'))
    for (let i = 0; i < 3; i++) dp.append(cardBackEl());
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
  // players who RECEIVED a whole hand (swap/rotate): their count jump and
  // fresh cards are the move itself, not draws from the pile
  const gotHand = new Set(fx.filter(f => f.kind === 'handsMoved')
    .flatMap(f => f.moves.map(m => m[1])));
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
    } else if (f.kind === 'handsMoved'){
      bigSplash('⇆', f.swap ? 'HANDS SWAPPED!' : 'HANDS ROTATE!', 'blue mid', stagger());
    } else if (f.kind === 'jumpin'){
      if (f.player === name) bigSplash('⚡', 'JUMPED IN!', 'blue', stagger());
      else seatBadge(f.player, '⚡ jumped in', 'skip');
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
      if (gotHand.has(name)) continue;
      const slot = document.querySelector('#hand .slot[data-cid="' + f.id + '"]');
      if (!slot) continue;
      slot.firstChild.style.visibility = 'hidden';
      flyClone(cardBackEl(), f.from, rect(slot),
               {delay:f.delay, onDone: () => { slot.firstChild.style.visibility = ''; }});
    } else if (f.kind === 'oppDraw'){
      if (gotHand.has(f.player)) continue;
      const s = seatOf(f.player);
      if (!s) continue;
      for (let i = 0; i < Math.min(f.count, 4); i++)
        flyClone(cardBackEl(true), f.from, rect(s), {delay:i*90, dur:380});
    } else if (f.kind === 'handsMoved'){
      // little card-back convoys travel each (from -> to) leg; the own
      // hand sits at the bottom of the screen rather than in a seat
      const spotOf = p => p === name ? $('hand') : seatOf(p);
      for (const [from, to] of f.moves){
        const a = spotOf(from), b = spotOf(to);
        if (!a || !b) continue;
        for (let i = 0; i < 3; i++)
          flyClone(cardBackEl(true), rect(a), rect(b), {delay:120 + i*110, dur:520});
      }
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
async function sendPlay(cardId, color, target){
  const r = await api('/api/play?card_id=' + cardId +
    (color ? '&color=' + color : '') +
    (target ? '&swap_with=' + encodeURIComponent(target) : ''), {method:'POST'});
  if (!r.ok) toast(r.error); else lastPlayedId = cardId;
}
// cards the server flagged as needing a swap target get a player picker
// (after the color wheel, if the card is also a wild)
let pendingSwap = null; // {id, color}
function openSwapModal(cardId, color){
  pendingSwap = {id: cardId, color};
  const box = document.querySelector('#swap-modal .swap-list');
  box.innerHTML = '';
  for (const p of state.players){
    if (p === name) continue;
    const b = document.createElement('button');
    const n = state.counts[p];
    b.textContent = p + (n === undefined ? '' : ' — ' + n + ' card' + (n === 1 ? '' : 's'));
    b.onclick = (e) => {
      e.stopPropagation();
      $('swap-modal').hidden = true;
      const ps = pendingSwap; pendingSwap = null;
      if (ps) sendPlay(ps.id, ps.color, p);
    };
    box.append(b);
  }
  $('swap-modal').hidden = false;
}
$('swap-modal').onclick = (e) => {
  if (e.target === $('swap-modal')){ $('swap-modal').hidden = true; pendingSwap = null; }
};

async function playCard(card){
  if (card.value === 'Wild' || card.value === 'Wild4'){
    pendingWild = card;
    $('color-modal').hidden = false;
    return;
  }
  if (state.swapTargets.has(card.id)){ openSwapModal(card.id, null); return; }
  sendPlay(card.id, null, null);
}

document.querySelectorAll('#color-modal .wheel button').forEach(b => {
  b.onclick = (e) => {
    e.stopPropagation();
    $('color-modal').hidden = true;
    if (!pendingWild) return;
    const id = pendingWild.id; pendingWild = null;
    if (state.swapTargets.has(id)){ openSwapModal(id, b.dataset.color); return; }
    sendPlay(id, b.dataset.color, null);
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
$('uno-btn').onclick = async () => {
  const r = await api('/api/uno', {method:'POST'}); if (!r.ok) toast(r.error);
};
$('ready-btn').onclick = async () => {
  const r = await api('/api/ready?on=' + !state.ready.includes(name), {method:'POST'});
  if (!r.ok) toast(r.error);
};
$('start-btn').onclick = async () => {
  // last line of defence against playing a ruleset nobody sent
  const unsent = appliedText !== null &&
                 $('rules-text').value.trim() !== appliedText.trim();
  if (unsent && confirm('The house rules in the editor have not been ' +
                        'submitted.\nSubmit them before starting?')){
    if (!await applyRules()) return;   // parse error: stay in the lobby
  }
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
// what the SERVER is actually playing; the textarea is only a draft until
// this is sent. Toggling a preset used to change the text and nothing else,
// which looked exactly like a broken rule.
let appliedText = null;

async function applyRules(){
  if (!code || !name) return false;   // not in a room yet: nothing to send to
  const text = $('rules-text').value;
  const r = await api('/api/rules', {method:'POST', body: text});
  const s = $('rules-status');
  if (r.ok){
    appliedText = text;
    s.textContent = 'Rules applied - this is what the game will use';
    s.className = 'ok';
  } else {
    s.textContent = r.error; s.className = 'err';
  }
  markRulesDirty();
  return r.ok;
}

// nag whenever the box has drifted from what was actually sent
function markRulesDirty(){
  renderHl();   // every programmatic editor write passes through here or
                // checkRules; with transparent text the overlay IS the display
  const dirtyRules =
    appliedText !== null && $('rules-text').value.trim() !== appliedText.trim();
  $('rules-btn').classList.toggle('needs-apply', dirtyRules);
  $('rules-btn').textContent = dirtyRules ? 'Submit rules *' : 'Submit rules';
}

$('rules-btn').onclick = applyRules;

/* ---------- rules editor helpers ---------- */
let lastLoaded = '';
let checkT = null;

async function checkRules(){
  const text = $('rules-text').value;
  const st = $('check-status');
  renderHl();
  syncRecipes();
  if (!text.trim()){ st.textContent = ''; return; }
  try {
    const r = await api('/api/check-rules', {method:'POST', body:text});
    if (r.ok){
      const warns = r.warnings || [];
      st.textContent = '✓ ' + r.num_rules + ' rules ready' +
        (r.deals ? ' · deals ' + r.deals + ' cards' : '') +
        (r.timer === null || r.timer === undefined ? '' :
         r.timer === 0 ? ' · no turn timer' : ' · ' + r.timer + 's turns');
      // keep the Table row honest whatever wrote the text (typing, modes,
      // another player's update) - but never fight an input being edited
      if (!$('set-deal').matches(':focus'))
        $('set-deal').value = r.deals || DEFAULT_DEAL;
      if (!$('set-timer').matches(':focus'))
        $('set-timer').value =
          (r.timer === null || r.timer === undefined) ? DEFAULT_TIMER : r.timer;
      st.className = warns.length ? 'warn' : 'ok';
      // the server names the snippet to insert (w.fix); w.kind implies where
      for (const w of warns){
        const line = document.createElement('div');
        line.textContent = '⚠ ' + w.message;
        if (w.fix){
          const b = document.createElement('button');
          b.className = 'small';
          b.textContent = 'add ‘' + w.fix + '’';
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
$('rules-text').addEventListener('input', () => { markRulesDirty(); scheduleCheck(); });

/* one-click warning fix: splice w.fix into the named rule, where depending
   on the kind - 'play the card' first in the "do" line (like every
   built-in), the color effect right after 'play the card', 'advance turn'
   last, 'your turn' into the WHEN clause. Duplicate names: the LAST
   definition is the live one. */
function applyFix(w){
  const ta = $('rules-text');
  const src = ta.value;
  const headRe = new RegExp('rule\\s*"' +
    w.rule.replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '"', 'gi');
  let head = null, m;
  while ((m = headRe.exec(src))) head = m;
  const doMatch = head && /\bdo\b[ \t]*/.exec(src.slice(head.index));
  const lost = () => { toast('could not find that rule anymore - re-checking'); checkRules(); };
  if (!doMatch){ lost(); return; }
  if (w.kind === 'missing_play'){
    const at = head.index + doMatch.index + doMatch[0].length;
    ta.value = src.slice(0, at) + w.fix + ', ' + src.slice(at);
  } else if (w.kind === 'missing_set_color'){
    // this warning only fires for rules that DO play the card
    const playRe = /play\s+the\s+card/g;
    playRe.lastIndex = head.index + doMatch.index;
    const pm = playRe.exec(src);
    if (!pm){ lost(); return; }
    const at = pm.index + pm[0].length;
    ta.value = src.slice(0, at) + ', ' + w.fix + src.slice(at);
  } else if (w.kind === 'missing_turn'){
    // this one splices into the WHEN clause: guard the whole condition,
    // adding parens when an 'or' would change meaning under the tighter 'and'
    const whenMatch = /\bwhen\b[ \t]*/.exec(src.slice(head.index));
    if (!whenMatch || whenMatch.index > doMatch.index){ lost(); return; }
    const condStart = head.index + whenMatch.index + whenMatch[0].length;
    const condEnd = head.index + doMatch.index;
    const raw = src.slice(condStart, condEnd);
    const sep = (raw.match(/\s*$/) || [' '])[0] || ' ';
    const cond = raw.trim();
    const guarded = (/\bor\b/.test(cond) ? '(' + cond + ')' : cond) + ' and ' + w.fix;
    ta.value = src.slice(0, condStart) + guarded + sep + src.slice(condEnd);
  } else {
    const lineEnd = src.indexOf('\n', head.index + doMatch.index);
    const at = lineEnd === -1 ? src.length : lineEnd;
    ta.value = src.slice(0, at).replace(/[ \t]+$/, '') + ', ' + w.fix + src.slice(at);
  }
  checkRules();
}

// the toggles compose: any mix of stacking, draw-until, jump-in and 7-0
function setPreset(stacking, drawuntil, jumpin, sevenzero){
  const ta = $('rules-text');
  if (ta.value.trim() !== lastLoaded.trim() &&
      !confirm('Replace the current rule text?')) return;
  $('toggle-stacking').classList.toggle('active', stacking);
  $('toggle-drawuntil').classList.toggle('active', drawuntil);
  $('toggle-jumpin').classList.toggle('active', jumpin);
  $('toggle-sevenzero').classList.toggle('active', sevenzero);
  ta.value = presetText();
  lastLoaded = ta.value;
  checkRules();
  loadOverrideList();
  // clicking a toggle IS the decision - send it, or the lobby would show a
  // preset the server never received
  applyRules();
}
const toggleOn = id => $(id).classList.contains('active');
const flip = (id) => setPreset(
  toggleOn('toggle-stacking') !== (id === 'toggle-stacking'),
  toggleOn('toggle-drawuntil') !== (id === 'toggle-drawuntil'),
  toggleOn('toggle-jumpin') !== (id === 'toggle-jumpin'),
  toggleOn('toggle-sevenzero') !== (id === 'toggle-sevenzero'));
$('preset-standard').onclick = () => setPreset(false, false, false, false);
$('toggle-stacking').onclick = () => flip('toggle-stacking');
$('toggle-drawuntil').onclick = () => flip('toggle-drawuntil');
$('toggle-jumpin').onclick = () => flip('toggle-jumpin');
$('toggle-sevenzero').onclick = () => flip('toggle-sevenzero');

/* the Table row edits the directive lines surgically - unlike the preset
   toggles it never replaces the rest of the text, so hand-written rules
   survive. Changing a setting IS the decision, so it submits like a
   toggle. */
function applySettingsToText(){
  const ta = $('rules-text');
  if (ta.value.trim() === ''){
    // empty editor: seed the full preset text (which includes settings)
    ta.value = presetText();
  } else {
    const lines = ta.value.split('\n').filter(l =>
      !/^\s*deal\s+\d+\s+cards?\s*$/i.test(l) &&
      !/^\s*turn\s+timer\b/i.test(l));
    let insertAt = 0;
    lines.forEach((l, i) => { if (/^\s*use\s+/i.test(l)) insertAt = i + 1; });
    const add = settingsLines();
    if (add) lines.splice(insertAt, 0, ...add.trimEnd().split('\n'));
    ta.value = lines.join('\n');
  }
  lastLoaded = ta.value;
  checkRules();
  applyRules();
}
$('set-deal').onchange = applySettingsToText;
$('set-timer').onchange = applySettingsToText;

/* ---------- house-rule recipe cards ----------
   A recipe is a named rule (or a settings pair) the card inserts into the
   text; the text stays the single source of truth. Card state is derived
   from the text by name-match, the same machinery preset overrides use,
   so hand-editing the rule flips the card and vice versa. */
const RECIPES = [
  { id:'noaf', cls:'r-red', g:'⊘', title:'No action finish',
    desc:'can’t go out on a skip, reverse, +2, +4 or wild',
    rule:'no action finish',
    text: () => 'rule "no action finish" priority 200:\n' +
      '  when card is action and hand size = 1\n' +
      '  do reject "no going out on an action card"' },
  { id:'t4', cls:'r-blue', g:'+4', title:'Targeted +4',
    desc:'a wild +4 hits a player you pick, not the next one',
    rule:'play plus four', marker:'chosen player draws', conflicts:['no4'],
    text: () => 'rule "play plus four" priority 110:\n' +
      '  when card is plus four and your turn\n' +
      '  do play the card, set color to declared, chosen player draws 4 cards, advance turn' },
  { id:'speed', cls:'r-yellow', g:'⚡', title:'Speed UNO',
    desc:'deal 5 cards, 10-second turns', settings:{deal:5, timer:10} },
  { id:'sevens', cls:'r-green', g:'7', title:'Cruel sevens',
    desc:'a 7 makes everyone else draw', param:{def:2, min:1, max:10}, suffix:'cards',
    rule:'cruel sevens',
    paramRe:/rule "cruel sevens"[\s\S]*?everyone else draws (\d+)/,
    text: n => 'rule "cruel sevens" priority 60:\n' +
      '  when card is 7 and (card matches color or card matches value) and your turn\n' +
      '  do play the card, set color from card, everyone else draws ' + n + ' cards, advance turn' },
  { id:'panic', cls:'r-red', g:'∅', title:'Endgame panic',
    desc:'draw pile under 10: every draw comes doubled',
    rule:'endgame panic',
    text: () => 'rule "endgame panic" priority 5:\n' +
      '  when player draws and your turn and draw pile < 10\n' +
      '  do draw 2 cards' },
  { id:'hoard', cls:'r-blue', g:'🂠', title:'No hoarding',
    desc:'no drawing while holding more than', param:{def:15, min:5, max:29}, suffix:'cards',
    rule:'no hoarding',
    paramRe:/rule "no hoarding"[\s\S]*?hand size > (\d+)/,
    text: n => 'rule "no hoarding" priority 200:\n' +
      '  when player draws and hand size > ' + n + '\n' +
      '  do reject "you have enough cards already"' },
  { id:'no4', cls:'r-yellow', g:'✕4', title:'No +4s',
    desc:'wild +4s become dead cards — unplayable',
    line:'remove rule "play plus four"', conflicts:['t4'] },
  { id:'tax', cls:'r-green', g:'+2', title:'Leader tax',
    desc:'while someone is on their last card, +2s double and hit a player you pick',
    rule:'leader tax',
    text: () => 'rule "leader tax" priority 105:\n' +
      '  when card is plus two and any opponent has 1 card and your turn\n' +
      '  do play the card, set color from card, chosen player draws 4 cards, advance turn' },
];

function lineRe(r){
  const esc = r.line.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp('^\\s*' + esc + '\\s*$', 'm');
}

function recipeOn(r, t){
  if (r.line) return lineRe(r).test(t);
  if (r.settings)
    return new RegExp('^\\s*deal ' + r.settings.deal + ' cards\\s*$', 'm').test(t) &&
      new RegExp('^\\s*turn timer ' + r.settings.timer + ' seconds\\s*$', 'm').test(t);
  if (!new RegExp('^\\s*rule "' + r.rule + '"', 'm').test(t)) return false;
  return r.marker ? t.includes(r.marker) : true;
}

// drop a named rule: its header line, its indented body, one trailing blank
function removeRuleBlock(text, ruleName){
  const out = []; let skip = false;
  for (const l of text.split('\n')){
    if (new RegExp('^\\s*rule "' + ruleName + '"').test(l)){ skip = true; continue; }
    if (skip){
      if (/^\s+\S/.test(l)) continue;
      skip = false;
      if (l.trim() === '') continue;
    }
    out.push(l);
  }
  return out.join('\n');
}

function appendRecipe(text, r){
  const n = r.param ? (parseInt($('rp-' + r.id).value, 10) || r.param.def) : null;
  return text.replace(/\s*$/, '') + '\n\n' + r.text(n) + '\n';
}

function stripRecipe(t, r){
  if (r.line) return t.split('\n').filter(l => !lineRe(r).test(l)).join('\n');
  if (r.rule) return removeRuleBlock(t, r.rule);
  return t;
}

// a directive line must sit AFTER the use line it subtracts from
function insertLine(t, line){
  const lines = t.split('\n');
  let at = 0;
  lines.forEach((l, i) => { if (/^\s*use\s+/i.test(l)) at = i + 1; });
  lines.splice(at, 0, line);
  return lines.join('\n');
}

function toggleRecipe(r){
  const ta = $('rules-text');
  if (ta.value.trim() === '') ta.value = presetText();
  if (r.settings){
    // ride the Table row: same directive lines, same surgical editing
    const on = recipeOn(r, ta.value);
    $('set-deal').value = on ? DEFAULT_DEAL : r.settings.deal;
    $('set-timer').value = on ? DEFAULT_TIMER : r.settings.timer;
    applySettingsToText();
    return;
  }
  const wasOn = recipeOn(r, ta.value);
  let t = stripRecipe(ta.value, r);
  if (!wasOn){
    // two recipes fighting over the same rule can't both hold
    for (const cid of (r.conflicts || [])){
      const c = RECIPES.find(x => x.id === cid);
      if (c && recipeOn(c, t)){
        t = stripRecipe(t, c);
        toast(r.title + ' replaces ' + c.title);
      }
    }
    t = r.line ? insertLine(t, r.line) : appendRecipe(t, r);
  }
  ta.value = t;
  lastLoaded = t;
  checkRules();
  applyRules();
}

function syncRecipes(){
  const t = $('rules-text').value;
  for (const r of RECIPES){
    $('rc-' + r.id).classList.toggle('on', recipeOn(r, t));
    if (r.paramRe && !$('rp-' + r.id).matches(':focus')){
      const m = t.match(r.paramRe);
      if (m) $('rp-' + r.id).value = m[1];
    }
  }
}

for (const r of RECIPES){
  const d = document.createElement('div');
  d.className = 'recipe'; d.id = 'rc-' + r.id;
  d.setAttribute('role', 'button'); d.tabIndex = 0;
  d.innerHTML = '<span class="r-mini ' + r.cls + '" data-g="' + r.g + '"></span>' +
    '<span><span class="r-t">' + r.title + '</span><span class="r-d">' + r.desc +
    (r.param ? ' <input id="rp-' + r.id + '" type="number" min="' + r.param.min +
      '" max="' + r.param.max + '" value="' + r.param.def + '"> ' + r.suffix : '') +
    '</span></span>';
  d.onclick = () => toggleRecipe(r);
  d.onkeydown = e => {
    if (e.key === 'Enter' || e.key === ' '){ e.preventDefault(); toggleRecipe(r); }
  };
  $('recipes').appendChild(d);
  if (r.param){
    const inp = $('rp-' + r.id);
    inp.onclick = e => e.stopPropagation();
    inp.onkeydown = e => e.stopPropagation();
    inp.onchange = e => {
      e.stopPropagation();
      if (!$('rc-' + r.id).classList.contains('on')) return;
      const ta = $('rules-text');
      const t = appendRecipe(removeRuleBlock(ta.value, r.rule), r);
      ta.value = t; lastLoaded = t;
      checkRules(); applyRules();
    };
  }
}

document.querySelectorAll('.cheat code').forEach(c => c.onclick = () => {
  const ta = $('rules-text');
  ta.setRangeText(c.textContent, ta.selectionStart, ta.selectionEnd, 'end');
  ta.focus();
  renderHl();
  scheduleCheck();
});

/* ---------- smart editor: coloring, autocomplete, caret help ----------
   The textarea's own text is transparent; a synced <pre> behind it carries
   the colors. Every programmatic value-set flows through checkRules or
   markRulesDirty, both of which re-render, so the display never lies. */
const ED = $('rules-text');

function escH(s){
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function renderHl(){
  let mode = 'top';
  const html = ED.value.split('\n').map(line => {
    // a # opens a comment only outside quotes (an even count precedes it)
    const cmM = line.match(/#(?=(?:[^"]*"[^"]*")*[^"]*$)/);
    let code = line, cm = '';
    if (cmM){ code = line.slice(0, cmM.index); cm = line.slice(cmM.index); }
    const first = (code.match(/^\s*([a-z]+)/i) || [])[1];
    if (first && /^(rule|use|remove|deal|turn)$/i.test(first)) mode = 'top';
    let out = '';
    const re = /("[^"]*"?)|(\d+)|([A-Za-z][A-Za-z']*)|(\s+)|(.)/g;
    let m;
    while ((m = re.exec(code))){
      if (m[1]) out += '<span class="e-str">' + escH(m[1]) + '</span>';
      else if (m[2]) out += '<span class="e-num">' + m[2] + '</span>';
      else if (m[3]){
        const w = m[3].toLowerCase();
        if (w === 'when'){ mode = 'cond'; out += '<span class="e-kw">' + m[3] + '</span>'; }
        else if (w === 'do'){ mode = 'eff'; out += '<span class="e-kw">' + m[3] + '</span>'; }
        else if (w === 'and' || w === 'or' || w === 'not')
          out += '<span class="e-kw">' + m[3] + '</span>';
        else if (mode === 'top' &&
                 /^(rule|priority|use|remove|deal|turn|timer|seconds?|cards?|off)$/.test(w))
          out += '<span class="e-kw">' + m[3] + '</span>';
        else if (mode === 'cond') out += '<span class="e-cond">' + escH(m[3]) + '</span>';
        else if (mode === 'eff') out += '<span class="e-eff">' + escH(m[3]) + '</span>';
        else out += escH(m[3]);
      }
      else if (m[4]) out += m[4];
      else out += escH(m[5]);
    }
    if (cm) out += '<span class="e-cm">' + escH(cm) + '</span>';
    return out;
  }).join('\n');
  $('hl').innerHTML = html + '\n';
}

/* the cheat sheet is the single source of phrases: harvest its entries so
   autocomplete and caret help stay in sync with the DSL automatically */
function phrasePat(t){
  let e = t.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  e = e.replace(/"[^"]*"/, '"[^"]*"');
  e = e.replace(/\b\d+\b/g, '\\d+');
  e = e.replace(/\b(red|yellow|green|blue)\b/, '(?:red|yellow|green|blue)');
  return new RegExp(e, 'gi');
}
const ACD = { cond:[], eff:[], top:[] };
const PHRASES = [];
{
  let group = '';
  document.querySelectorAll('.cheat h4, .cheat code').forEach(el => {
    if (el.tagName === 'H4'){ group = el.textContent; return; }
    const item = { t: el.textContent, d: el.title || '' };
    PHRASES.push({ ...item, re: phrasePat(item.t) });
    if (/Condition/i.test(group)) ACD.cond.push(item);
    else if (/Effect/i.test(group)) ACD.eff.push(item);
    else ACD.top.push(item);
  });
  ACD.top.unshift({ t: 'rule "my rule" priority 60:',
    d: 'start a new rule - follow with a when line and a do line' });
}

let acItems = [], acSel = 0, acStart = 0;

function acContext(){
  const pos = ED.selectionStart;
  if (pos !== ED.selectionEnd) return null;
  const before = ED.value.slice(0, pos);
  const ls = before.lastIndexOf('\n') + 1;
  const line = before.slice(ls);
  if (/^\s*#/.test(line)) return null;
  let ctx = null, m;
  if (/\bdo\b/i.test(line) && (m = line.match(/^([\s\S]*(?:\bdo\b|,))([^,]*)$/i)))
    ctx = { kind:'eff', start: ls + m[1].length, frag: m[2] };
  else if ((m = line.match(/^([\s\S]*(?:\bwhen\b|\band\b|\bor\b|\bnot\b|\())([^()]*)$/i)))
    ctx = { kind:'cond', start: ls + m[1].length, frag: m[2] };
  else if (/^\s*rule\b/i.test(line)) return null;
  else {
    m = line.match(/^(\s*)([\s\S]*)$/);
    ctx = { kind:'top', start: ls + m[1].length, frag: m[2] };
  }
  const lead = ctx.frag.match(/^\s*/)[0].length;
  ctx.start += lead;
  ctx.frag = ctx.frag.slice(lead);
  return ctx;
}

function acFilter(list, frag){
  const f = frag.toLowerCase();
  const pre = [], sub = [];
  for (const it of list){
    const t = it.t.toLowerCase();
    if (t.startsWith(f)) pre.push(it);
    else if (f.length >= 2 && t.includes(f)) sub.push(it);
  }
  return pre.concat(sub).slice(0, 8);
}

let edLineH = 0, edMirror = null;
function caretXY(){
  if (!edMirror){
    edMirror = document.createElement('div');
    edMirror.id = 'ed-mirror';
    edMirror.setAttribute('aria-hidden', 'true');
    $('ed-wrap').appendChild(edMirror);
  }
  edMirror.textContent = ED.value.slice(0, ED.selectionStart);
  const mark = document.createElement('span');
  mark.textContent = '​';
  edMirror.appendChild(mark);
  return { x: mark.offsetLeft, y: mark.offsetTop - ED.scrollTop };
}

function paintAc(){
  const p = $('ac-pop');
  p.innerHTML = '';
  acItems.forEach((it, i) => {
    const d = document.createElement('div');
    if (i === acSel) d.className = 'sel';
    d.innerHTML = '<b>' + escH(it.t) + '</b>' +
      (it.d ? '<small>' + escH(it.d) + '</small>' : '');
    d.onmousedown = e => e.preventDefault();  // keep focus in the editor
    d.onclick = () => acAccept(it);
    d.onmouseenter = () => { acSel = i; paintAc(); setHelp(it); };
    p.appendChild(d);
  });
}

function placeAc(){
  const p = $('ac-pop');
  if (!edLineH) edLineH = parseFloat(getComputedStyle(ED).lineHeight) || 18;
  const { x, y } = caretXY();
  const wrap = $('ed-wrap');
  p.style.left = Math.max(0, Math.min(x, wrap.clientWidth - p.offsetWidth - 4)) + 'px';
  p.style.top = (y + edLineH + 2) + 'px';
}

function setHelp(it){
  $('phrase-help').innerHTML =
    it ? '<b>' + escH(it.t) + '</b> — ' + escH(it.d) : '';
}

function updateHelp(){
  if (!$('ac-pop').hidden && acItems[acSel]){ setHelp(acItems[acSel]); return; }
  const pos = ED.selectionStart;
  const ls = ED.value.lastIndexOf('\n', pos - 1) + 1;
  let le = ED.value.indexOf('\n', pos);
  if (le < 0) le = ED.value.length;
  const line = ED.value.slice(ls, le), col = pos - ls;
  let best = null;
  for (const p of PHRASES){
    p.re.lastIndex = 0;
    let m;
    while ((m = p.re.exec(line))){
      if (m.index > col) break;
      if (col <= m.index + m[0].length){
        if (!best || m[0].length > best.t.length) best = { t: m[0], d: p.d };
        break;
      }
    }
  }
  setHelp(best);
}

function closeAc(){
  $('ac-pop').hidden = true;
  acItems = [];
  updateHelp();
}

function acAccept(it){
  ED.setRangeText(it.t, acStart, ED.selectionStart, 'end');
  renderHl();
  markRulesDirty();
  scheduleCheck();
  closeAc();
  ED.focus();
}

function updateAc(){
  const ctx = acContext();
  if (!ctx || !ctx.frag){ closeAc(); return; }
  const list = ACD[ctx.kind];
  acItems = acFilter(list, ctx.frag);
  if (!acItems.length ||
      (acItems.length === 1 && acItems[0].t.toLowerCase() === ctx.frag.toLowerCase())){
    closeAc();
    return;
  }
  acStart = ctx.start;
  acSel = 0;
  paintAc();
  $('ac-pop').hidden = false;
  placeAc();
  updateHelp();
}

ED.addEventListener('input', () => { renderHl(); updateAc(); });
ED.addEventListener('scroll', () => {
  $('hl').scrollTop = ED.scrollTop;
  $('hl').scrollLeft = ED.scrollLeft;
  if (!$('ac-pop').hidden) closeAc();
});
ED.addEventListener('click', () => { closeAc(); updateHelp(); });
ED.addEventListener('keyup', e => {
  if ($('ac-pop').hidden &&
      ['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown', 'Home', 'End'].includes(e.key))
    updateHelp();
});
ED.addEventListener('blur', () => setTimeout(() => { $('ac-pop').hidden = true; }, 150));
ED.addEventListener('keydown', e => {
  if ($('ac-pop').hidden) return;
  if (e.key === 'ArrowDown'){
    e.preventDefault(); acSel = (acSel + 1) % acItems.length; paintAc(); updateHelp();
  } else if (e.key === 'ArrowUp'){
    e.preventDefault();
    acSel = (acSel + acItems.length - 1) % acItems.length; paintAc(); updateHelp();
  } else if (e.key === 'Enter' || e.key === 'Tab'){
    e.preventDefault(); acAccept(acItems[acSel]);
  } else if (e.key === 'Escape'){
    e.preventDefault(); closeAc();
  }
});

/* the current preset's rules, offered for copy-and-customize: clicking one
   appends its full text, and the same name makes the copy replace the
   built-in when the ruleset is parsed */
async function loadOverrideList(){
  const box = $('override-list');
  try {
    const r = await api('/api/preset-rules?name=' + encodeURIComponent(presetName()));
    if (!r.ok) return;
    // the 7-0 add-on's rules are overridable too when its toggle is on
    if (sevenZeroOn()){
      const r2 = await api('/api/preset-rules?name=' + encodeURIComponent('seven zero'));
      if (r2.ok) r.text += '\n\n' + r2.text;
    }
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

/* rule builder: conditions form LINES - every line must hold ("and"), and
   a line holds if any chip in it does ("or"). Click a chip to flip it to
   "not", click its × to remove it. This shape (and-of-ors of possibly
   negated chips) can express anything the text grammar can. Effects stay
   one flat chip list. */
let builderRows = [[{t:'your turn', neg:false}]];   // the usual guard
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
  const when = WHEN_OPTIONS[$('b-when').value][0];
  $('b-when-n').hidden = !when.includes('N');
  $('b-when-color').hidden = !when.includes('C');
  // card numbers stop at 9; the other N (pending draws) is unbounded
  if (when === 'card is N') $('b-when-n').max = 9;
  else $('b-when-n').removeAttribute('max');
  const eff = EFF_OPTIONS[$('b-eff').value][0];
  $('b-eff-n').hidden = !eff.includes('N');
  $('b-eff-color').hidden = !eff.includes('C');
  $('b-eff-msg').hidden = !eff.includes('"M"');
}
$('b-when').onchange = syncBuilderInputs;
$('b-eff').onchange = syncBuilderInputs;
syncBuilderInputs();

function builderName(){
  return $('b-name').value.trim() || 'my rule ' + (customRuleN + 1);
}
function condText(){
  if (!builderRows.length) return 'always';
  return builderRows.map(row => {
    const s = row.map(c => (c.neg ? 'not ' : '') + c.t).join(' or ');
    return row.length > 1 ? '(' + s + ')' : s;
  }).join(' and ');
}
function builderText(){
  return 'rule "' + builderName() + '" priority ' + $('b-prio').value + ':\n' +
         '  when ' + condText() + '\n' +
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
function renderCondRows(){
  const box = $('b-conds');
  box.innerHTML = '';
  builderRows.forEach((row, ri) => {
    const div = document.createElement('div');
    div.className = 'b-cond-row';
    row.forEach((c, ci) => {
      if (ci){
        const j = document.createElement('span');
        j.className = 'cjoin'; j.textContent = 'or';
        div.append(j);
      }
      const s = document.createElement('span');
      s.className = 'cchip' + (c.neg ? ' neg' : '');
      s.append(document.createTextNode((c.neg ? 'not ' : '') + c.t));
      s.title = c.neg ? 'click to require it again' : 'click to require the opposite (not)';
      s.onclick = () => { c.neg = !c.neg; renderChips(); };
      const x = document.createElement('b');
      x.textContent = '×'; x.title = 'remove';
      x.onclick = e => {
        e.stopPropagation();
        row.splice(ci, 1);
        if (!row.length) builderRows.splice(ri, 1);
        renderChips();
      };
      s.append(x);
      div.append(s);
    });
    const orBtn = document.createElement('button');
    orBtn.className = 'small';
    orBtn.textContent = '+ or…';
    orBtn.title = 'add the condition picked above to this line as an alternative';
    orBtn.onclick = () => addCond(ri);
    div.append(orBtn);
    const rmBtn = document.createElement('button');
    rmBtn.className = 'small b-row-x';
    rmBtn.textContent = '× line';
    rmBtn.title = 'remove this whole line';
    rmBtn.onclick = () => { builderRows.splice(ri, 1); renderChips(); };
    div.append(rmBtn);
    box.append(div);
  });
}
function renderChips(){
  renderCondRows();
  renderChipList($('b-effs'), builderEffs);
  // the guard only counts when a whole line is exactly "your turn" -
  // or-ing something onto it weakens it (matches the checker's rule)
  $('b-turn-hint').hidden = builderRows.some(r =>
    r.length === 1 && !r[0].neg && r[0].t === 'your turn');
  const untouched = builderRows.length === 1 && builderRows[0].length === 1 &&
    !builderRows[0][0].neg && builderRows[0][0].t === 'your turn';
  // preview only once the rule differs from the untouched default
  $('b-preview').textContent =
    (builderEffs.length || !untouched || $('b-name').value.trim())
      ? builderText() : '';
}
// a positive card-play condition means this rule will WIN the card click,
// so it must handle the whole play - pre-add the usual effects (once per
// composition, only into an empty effect list; all removable like any chip)
let autoFilled = false;
function addCond(ri){
  // an option that is itself an "or" (like "a matching card is played")
  // splits into separate chips of one line
  const parts = WHEN_OPTIONS[$('b-when').value][0]
    .replace('N', $('b-when-n').value || '0')
    .replace('C', $('b-when-color').value)
    .split(' or ');
  const fresh = parts.map(t => ({t, neg:false}));
  if (ri == null) builderRows.push(fresh);
  else for (const c of fresh){
    if (!builderRows[ri].some(o => o.t === c.t)) builderRows[ri].push(c);
  }
  if (!autoFilled && !builderEffs.length &&
      parts.some(t => t.startsWith('card ') || t === 'continues stack')){
    autoFilled = true;
    // mid-stack plays keep the turn, so no advance for "continues stack"
    builderEffs = parts.includes('continues stack')
      ? ['play the card', 'set color from card']
      : ['play the card', 'set color from card', 'advance turn'];
    toast('Added the usual play effects - remove any chip you don’t want');
  }
  renderChips();
}
$('b-add-cond').onclick = () => addCond(null);
// 'advance turn' / 'skip next player' end the turn, so keep exactly one of
// them at the tail: other effects slot in before it, a second one replaces it
const TURN_END = new Set(['advance turn', 'skip next player']);
$('b-add-eff').onclick = () => {
  let t = EFF_OPTIONS[$('b-eff').value][0];
  t = t.replace('N', $('b-eff-n').value || '1').replace('C', $('b-eff-color').value);
  if (t.includes('"M"')){
    // the reject message comes from its own input; quotes would end the
    // string early in the rule text, so they're dropped
    const msg = ($('b-eff-msg').value || 'not allowed').replace(/"/g, '').trim();
    t = t.replace('"M"', '"' + (msg || 'not allowed') + '"');
    // a reject discards every other effect anyway - a blocking rule IS
    // just the reject, so clear out anything already added
    if (builderEffs.length){
      builderEffs = [];
      toast('A blocking rule rejects the whole move - removed the other effects');
    }
  }
  const last = builderEffs[builderEffs.length - 1];
  if (TURN_END.has(t) && TURN_END.has(last)) builderEffs[builderEffs.length - 1] = t;
  else if (TURN_END.has(last) && !TURN_END.has(t))
    builderEffs.splice(builderEffs.length - 1, 0, t);
  else builderEffs.push(t);
  renderChips();
};
$('b-prio').onchange = renderChips;
$('b-name').addEventListener('input', renderChips);
function resetBuilder(){
  builderRows = [[{t:'your turn', neg:false}]];
  builderEffs = []; autoFilled = false;
  $('b-name').value = '';
  renderChips();
}
$('b-append').onclick = () => {
  if (!builderEffs.length){ toast('Add at least one effect first'); return; }
  const text = builderText();
  if ($('b-name').value.trim() === '') customRuleN++;
  const ta = $('rules-text');
  ta.value = ta.value.replace(/\s*$/, '\n\n') + text;
  ta.scrollTop = ta.scrollHeight;
  resetBuilder();
  checkRules();
};
$('b-clear').onclick = resetBuilder;
renderChips();

/* ---------- optional login + saved rule modes ---------- */
let auth = null; // {user, token, modes:[{name,text}]}

function setAuth(a){
  auth = a;
  if (a) localStorage.setItem('uno-auth', JSON.stringify({user:a.user, token:a.token}));
  else localStorage.removeItem('uno-auth');
  renderAuth();
}
function renderAuth(){
  $('login-form').hidden = !!auth;
  $('login-info').hidden = !auth;
  if (auth) $('login-who').textContent = '🔑 ' + auth.user + ' ';
  renderModes();
}
function renderModes(){
  $('modes-row').hidden = !auth;
  if (!auth) return;
  const box = $('mode-chips'); box.innerHTML = '';
  for (const m of auth.modes){
    const c = document.createElement('button');
    c.className = 'preset toggle';
    c.textContent = m.name;
    c.title = 'load "' + m.name + '" into the editor';
    c.onclick = () => loadMode(m);
    box.append(c);
    const x = document.createElement('button');
    x.className = 'small mode-del';
    x.textContent = '×';
    x.title = 'delete "' + m.name + '"';
    x.onclick = async () => {
      if (!confirm('Delete mode "' + m.name + '"?')) return;
      const r = await api('/api/mode-delete?token=' + auth.token +
                          '&mode=' + encodeURIComponent(m.name), {method:'POST'});
      if (r.ok){ auth.modes = r.modes; renderModes(); } else toast(r.error);
    };
    box.append(x);
  }
}
function loadMode(m){
  const ta = $('rules-text');
  if (ta.value.trim() !== lastLoaded.trim() &&
      !confirm('Replace the current rule text?')) return;
  ta.value = m.text;
  lastLoaded = m.text;
  $('toggle-stacking').classList.remove('active');
  $('toggle-drawuntil').classList.remove('active');
  checkRules();
  loadOverrideList();
}
$('login-btn').onclick = async () => {
  const u = $('login-user').value.trim(), p = $('login-pw').value;
  if (!u || !p){ $('login-err').textContent = 'enter a username and a password'; return; }
  const r = await api('/api/login', {method:'POST', body: u + '\n' + p});
  if (!r.ok){ $('login-err').textContent = r.error; return; }
  $('login-err').textContent = '';
  $('login-pw').value = '';
  setAuth({user:r.user, token:r.token, modes:r.modes});
  if (r.created) toast('Account created - welcome, ' + r.user + '!');
  if (!$('name-input').value) $('name-input').value = r.user;
};
$('login-pw').addEventListener('keydown', e => {
  if (e.key === 'Enter') $('login-btn').click();
});
$('logout-btn').onclick = () => setAuth(null);
$('mode-save').onclick = async () => {
  const mn = $('mode-name').value.trim();
  if (!mn){ toast('Give the mode a name first'); return; }
  const r = await api('/api/mode-save?token=' + auth.token +
                      '&mode=' + encodeURIComponent(mn),
                      {method:'POST', body: $('rules-text').value});
  if (r.ok){
    auth.modes = r.modes; $('mode-name').value = '';
    renderModes(); toast('Saved mode "' + mn + '"');
  } else toast(r.error);
};
// restore a remembered login (token dies with a server restart; that just
// means logging in again)
(async () => {
  try {
    const saved = JSON.parse(localStorage.getItem('uno-auth') || 'null');
    if (!saved) return;
    const r = await api('/api/me?token=' + saved.token, {method:'POST'});
    if (r.ok) setAuth({user:r.user, token:r.token, modes:r.modes});
    else localStorage.removeItem('uno-auth');
  } catch (e){}
})();
renderAuth();

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

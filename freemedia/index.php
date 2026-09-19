<?php
$uploadDir = __DIR__ . '/uploads/';
$message = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_FILES['files'])) {
    $saved = 0;
    $names = $_FILES['files']['name'];
    $temps = $_FILES['files']['tmp_name'];
    $errors = $_FILES['files']['error'];

    foreach ($names as $index => $originalName) {
        if ($errors[$index] !== UPLOAD_ERR_OK) {
            continue;
        }
        $safeName = basename(str_replace('\\', '/', $originalName));
        if ($safeName === '' || $safeName === '.' || $safeName === '..') {
            continue;
        }
        if (move_uploaded_file($temps[$index], $uploadDir . $safeName)) {
            chmod($uploadDir . $safeName, 0644);
            $saved++;
        }
    }
    $message = $saved > 0 ? "$saved file(s) uploaded successfully." : 'No files were uploaded.';
}

$files = array_values(array_filter(scandir($uploadDir), fn($name) => $name[0] !== '.'));
natcasesort($files);
$imageTypes = ['jpg', 'jpeg', 'png', 'gif', 'webp'];
function e($value) { return htmlspecialchars($value, ENT_QUOTES, 'UTF-8'); }
function formatSize($bytes) {
    if ($bytes >= 1048576) return number_format($bytes / 1048576, 1) . ' MB';
    if ($bytes >= 1024) return number_format($bytes / 1024, 1) . ' KB';
    return $bytes . ' B';
}
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>FreeMedia Asset Console</title>
  <style>
    :root { color-scheme:dark; --bg:#07111f; --panel:#0d1b2d; --line:#203a55; --text:#edf6ff; --muted:#91a8bf; --blue:#66b3ff; --cyan:#42dfc8; }
    * { box-sizing:border-box; }
    body { margin:0; min-height:100vh; color:var(--text); font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; background:radial-gradient(circle at 90% 0,#163d60 0,transparent 34%),var(--bg); }
    header { display:flex; align-items:center; justify-content:space-between; max-width:1180px; margin:auto; padding:24px 28px; border-bottom:1px solid rgba(255,255,255,.07); }
    .brand { display:flex; align-items:center; gap:12px; font-weight:800; }
    .logo { width:38px; height:38px; display:grid; place-items:center; border-radius:11px; color:#06101c; background:linear-gradient(135deg,var(--cyan),var(--blue)); }
    .online { color:#72efbd; font-size:12px; font-weight:700; letter-spacing:.5px; }
    main { max-width:1180px; margin:auto; padding:54px 28px 70px; }
    .hero { display:grid; grid-template-columns:1fr .85fr; gap:52px; align-items:center; margin-bottom:48px; }
    .eyebrow { color:var(--cyan); font-size:12px; font-weight:800; letter-spacing:1.5px; }
    h1 { margin:12px 0; font-size:clamp(38px,5vw,61px); letter-spacing:-2px; }
    .lead { max-width:590px; color:var(--muted); font-size:17px; line-height:1.7; }
    .upload { padding:24px; border:1px solid var(--line); border-radius:17px; background:linear-gradient(145deg,#10243a,#0a1726); box-shadow:0 25px 65px #0006; }
    .drop { display:block; padding:30px 18px; text-align:center; border:1px dashed #3b658a; border-radius:13px; cursor:pointer; background:#091725; transition:.2s; }
    .drop:hover,.drop.active { border-color:var(--cyan); background:#0b2030; }
    input[type=file] { display:none; }
    .upload-row { display:flex; align-items:center; justify-content:space-between; gap:14px; margin-top:15px; }
    #selection { color:var(--muted); font-size:13px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
    button { flex:none; border:0; border-radius:9px; padding:11px 17px; color:#06101c; font-weight:800; cursor:pointer; background:linear-gradient(135deg,var(--cyan),var(--blue)); }
    .notice { margin-top:13px; color:#72efbd; font-size:13px; }
    .section-head { display:flex; align-items:end; justify-content:space-between; margin:0 0 18px; }
    h2 { margin:0; font-size:22px; }
    .count { color:var(--muted); font-size:13px; }
    .gallery { display:grid; grid-template-columns:repeat(4,minmax(0,1fr)); gap:16px; }
    .card { position:relative; min-width:0; overflow:hidden; border:1px solid var(--line); border-radius:14px; color:inherit; background:var(--panel); transition:transform .2s,border-color .2s; }
    .card:hover { transform:translateY(-3px); border-color:#477ca8; }
    .asset { display:block; color:inherit; text-decoration:none; }
    .thumb { aspect-ratio:16/10; width:100%; object-fit:cover; display:block; background:#091725; }
    .file-icon { aspect-ratio:16/10; display:grid; place-items:center; font-size:38px; color:var(--blue); background:linear-gradient(145deg,#0c2135,#122c46); }
    .meta { padding:13px 14px 15px; }
    .name { display:block; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; font-size:14px; font-weight:700; }
    .size { display:block; margin-top:5px; color:var(--muted); font-size:12px; }
    .actions { display:flex; gap:8px; margin-top:13px; }
    .action { flex:1; padding:8px 9px; border:1px solid #2d4c69; border-radius:8px; color:#b8d7f3; text-align:center; text-decoration:none; font-size:12px; font-weight:750; background:#0a1826; }
    .action.download { color:#07111f; border-color:transparent; background:linear-gradient(135deg,var(--cyan),var(--blue)); }
    @media(max-width:900px){.hero{grid-template-columns:1fr}.gallery{grid-template-columns:repeat(2,1fr)}}
    @media(max-width:540px){.gallery{grid-template-columns:1fr}.upload-row{align-items:stretch;flex-direction:column}button{width:100%}}
  </style>
</head>
<body>
<header>
  <div class="brand"><span class="logo">F</span><span>FreeMedia</span></div>
  <div class="online">● EDGE NODE ONLINE</div>
</header>
<main>
  <section class="hero">
    <div>
      <div class="eyebrow">NIMBUSGRID MEDIA SERVICES</div>
      <h1>Asset delivery console</h1>
      <p class="lead">Upload and manage files distributed through this regional media node. Open an asset in a new tab or download a local copy.</p>
    </div>
    <form class="upload" method="post" enctype="multipart/form-data">
      <label class="drop" id="drop" for="files"><strong>Drop files here or browse</strong><br><small>Multiple files supported · 16 MB per file</small></label>
      <input id="files" name="files[]" type="file" multiple required>
      <div class="upload-row"><span id="selection">No files selected</span><button type="submit">Upload files</button></div>
      <?php if ($message): ?><div class="notice"><?= e($message) ?></div><?php endif; ?>
    </form>
  </section>
  <div class="section-head"><h2>Media library</h2><span class="count"><?= count($files) ?> assets</span></div>
  <section class="gallery">
    <?php foreach ($files as $file):
      $ext = strtolower(pathinfo($file, PATHINFO_EXTENSION));
      $url = 'uploads/' . rawurlencode($file);
      $isImage = in_array($ext, $imageTypes, true);
    ?>
      <article class="card">
        <a class="asset" href="<?= e($url) ?>" target="_blank" rel="noopener">
          <?php if ($isImage): ?>
            <img class="thumb" src="<?= e($url) ?>" alt="<?= e($file) ?>" loading="lazy">
          <?php else: ?>
            <div class="file-icon">◇</div>
          <?php endif; ?>
        </a>
        <div class="meta">
          <span class="name"><?= e($file) ?></span>
          <span class="size"><?= e(strtoupper($ext ?: 'FILE')) ?> · <?= formatSize(filesize($uploadDir . $file)) ?></span>
          <div class="actions">
            <a class="action" href="<?= e($url) ?>" target="_blank" rel="noopener">Open</a>
            <a class="action download" href="download.php?file=<?= e(rawurlencode($file)) ?>">Download</a>
          </div>
        </div>
      </article>
    <?php endforeach; ?>
  </section>
</main>
<script>
const input=document.getElementById('files'),drop=document.getElementById('drop'),selection=document.getElementById('selection');
input.addEventListener('change',()=>selection.textContent=input.files.length?`${input.files.length} file(s) selected`:'No files selected');
for(const event of ['dragenter','dragover']) drop.addEventListener(event,e=>{e.preventDefault();drop.classList.add('active')});
for(const event of ['dragleave','drop']) drop.addEventListener(event,e=>{e.preventDefault();drop.classList.remove('active')});
drop.addEventListener('drop',e=>{input.files=e.dataTransfer.files;input.dispatchEvent(new Event('change'))});
</script>
</body>
</html>

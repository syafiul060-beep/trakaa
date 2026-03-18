const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const files = ['privacy.html', 'terms.html'];
const publicDir = path.join(root, 'public');
const distDir = path.join(root, 'dist');

if (!fs.existsSync(distDir)) {
  console.error('dist/ folder not found. Run npm run build first.');
  process.exit(1);
}

files.forEach((file) => {
  const src = path.join(publicDir, file);
  const dest = path.join(distDir, file);
  if (!fs.existsSync(src)) {
    console.error('Source not found:', src);
    process.exit(1);
  }
  try {
    fs.copyFileSync(src, dest);
    console.log('Copied', file, 'to dist/');
  } catch (err) {
    console.error('Error copying', file, err.message);
    process.exit(1);
  }
});

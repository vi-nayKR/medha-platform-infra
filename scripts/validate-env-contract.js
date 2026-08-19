import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, '../..');

function assertContains(relativeFilePath, expected) {
  const absolutePath = path.join(root, relativeFilePath);
  
  if (!fs.existsSync(absolutePath)) {
    console.error(`❌ Error: File not found: ${relativeFilePath}`);
    process.exit(1);
  }
  
  const content = fs.readFileSync(absolutePath, 'utf8');
  if (!content.includes(expected)) {
    console.error(`❌ Error: ${relativeFilePath} must contain "${expected}"`);
    process.exit(1);
  }
}

// 1. Validate medha-web
assertContains('medha-web/.env.development', 'VITE_API_BASE_URL=https://api-dev.medha.dev');
assertContains('medha-web/.env.production', 'VITE_API_BASE_URL=https://api.medha.dev');

// Wrangler pattern validation
const wranglerPath = path.join(root, 'medha-web/wrangler.jsonc');
if (fs.existsSync(wranglerPath)) {
  const wranglerContent = fs.readFileSync(wranglerPath, 'utf8');
  if (wranglerContent.includes('"pattern": "medha.dev"')) {
    assertContains('medha-web/wrangler.jsonc', '"pattern": "medha.dev"');
    assertContains('medha-web/wrangler.jsonc', '"pattern": "www.medha.dev"');
  } else {
    assertContains('medha-web/wrangler.jsonc', '"pattern": "dev.medha.dev"');
  }
}

// 2. Validate medha-admin-panel
assertContains('medha-admin-panel/.env.development', 'VITE_API_BASE_URL=https://api-dev.medha.dev');
assertContains('medha-admin-panel/.env.production', 'VITE_API_BASE_URL=https://api.medha.dev');

// 3. Validate medha-android
assertContains('medha-android/app/build.gradle.kts', 'https://api-dev.medha.dev/api/v2/');
assertContains('medha-android/app/build.gradle.kts', 'https://api.medha.dev/api/v2/');

// 4. Validate medha-infra Terraform configs
assertContains('medha-infra/terraform/cloudflare/main.tf', '"admin"');
assertContains('medha-infra/terraform/cloudflare/main.tf', '"admin-dev"');

console.log('✅ Cross-repository environment contract passed');

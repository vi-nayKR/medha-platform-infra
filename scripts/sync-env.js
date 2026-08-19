import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const rootDir = path.resolve(__dirname, '../..');

const app = process.argv[2];

if (!app) {
  console.error('usage: node sync-env.js <api|web|admin|android>');
  process.exit(2);
}

switch (app) {
  case 'api': {
    const example = path.join(rootDir, 'medha-api', '.env.example');
    const target = path.join(rootDir, 'medha-api', '.env');
    
    if (!fs.existsSync(example)) {
      console.error(`missing ${example}`);
      process.exit(1);
    }
    
    if (fs.existsSync(target)) {
      console.log('medha-api/.env already exists; leaving it untouched');
    } else {
      fs.copyFileSync(example, target);
      console.log('created medha-api/.env; add development values only');
    }
    break;
  }
  case 'web':
  case 'admin':
    console.log(`${app} uses committed .env.development/.env.production files; nothing to copy`);
    break;
  case 'android':
    console.log('android uses Gradle dev/prod product flavors; nothing to copy');
    break;
  default:
    console.error(`usage: node sync-env.js <api|web|admin|android>`);
    process.exit(2);
}

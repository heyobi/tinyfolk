#!/usr/bin/env node
// App Store Connect API yardımcısı (bağımlılık yok; Node 18+).
// Ortam değişkenleri: ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY (.p8 içeriği), BUNDLE_ID.
//
// Komutlar:
//   node scripts/asc.js ensure-app
//       Bundle ID kayıtlı değilse kaydeder; App Store Connect'te uygulama kaydı yoksa açıklayıcı bir hatayla durur.
//       GITHUB_OUTPUT'a app_id yazar.
//   node scripts/asc.js next-build-number <appId> [enAz]
//       App Store Connect'teki en yüksek build numarası + 1 (ya da enAz, hangisi büyükse). GITHUB_OUTPUT'a build_number yazar.
//   node scripts/asc.js profile <sertifikaSeriNo> <profilAdı>
//       Bu bundle ID + dağıtım sertifikası için App Store provisioning profilini bulur ya da oluşturur,
//       ~/Library/MobileDevice/Provisioning Profiles altına kurar. GITHUB_OUTPUT'a profile_name ve profile_uuid yazar.
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');

const API = 'https://api.appstoreconnect.apple.com';

function env(name) {
  const v = (process.env[name] || '').trim();
  if (!v) fail(`${name} ortam değişkeni boş. İlgili GitHub secret'ı eklendi mi?`);
  return v;
}

function fail(msg) {
  console.error(`::error::${msg}`);
  process.exit(1);
}

function output(key, value) {
  console.log(`${key}=${value}`);
  if (process.env.GITHUB_OUTPUT) fs.appendFileSync(process.env.GITHUB_OUTPUT, `${key}=${value}\n`);
}

function privateKey() {
  let raw = env('ASC_PRIVATE_KEY').replace(/^["']|["']$/g, '');
  raw = raw.replace(/\\n/g, '\n').trim() + '\n';
  return raw;
}

function token() {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  const head = b64({ alg: 'ES256', kid: env('ASC_KEY_ID'), typ: 'JWT' });
  const body = b64({ iss: env('ASC_ISSUER_ID'), iat: now, exp: now + 15 * 60, aud: 'appstoreconnect-v1' });
  const sig = crypto.sign('sha256', Buffer.from(`${head}.${body}`), { key: privateKey(), dsaEncoding: 'ieee-p1363' });
  return `${head}.${body}.${sig.toString('base64url')}`;
}

async function api(method, url, body) {
  const res = await fetch(url.startsWith('http') ? url : API + url, {
    method,
    headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) {
    let detail = text;
    try {
      detail = JSON.parse(text).errors.map((e) => `${e.title}: ${e.detail}`).join(' | ');
    } catch {}
    const err = new Error(`${method} ${url} -> ${res.status} ${detail}`);
    err.status = res.status;
    throw err;
  }
  return text ? JSON.parse(text) : {};
}

async function findBundleId(identifier) {
  const r = await api('GET', `/v1/bundleIds?filter[identifier]=${encodeURIComponent(identifier)}&limit=200`);
  return r.data.find((b) => b.attributes.identifier === identifier);
}

async function ensureApp() {
  const bundleId = env('BUNDLE_ID');
  let bid = await findBundleId(bundleId);
  if (!bid) {
    console.log(`Bundle ID ${bundleId} kayıtlı değil, kaydediliyor...`);
    try {
      const r = await api('POST', '/v1/bundleIds', {
        data: { type: 'bundleIds', attributes: { identifier: bundleId, name: bundleId.replace(/\./g, ' '), platform: 'IOS' } },
      });
      bid = r.data;
      console.log(`✓ Bundle ID kaydedildi (${bid.id}).`);
    } catch (e) {
      fail(`Bundle ID ${bundleId} kaydedilemedi (${e.message}). Apple Developer > Identifiers bölümünden elle kaydedin.`);
    }
  } else {
    console.log(`✓ Bundle ID ${bundleId} kayıtlı (${bid.id}).`);
  }

  const apps = await api('GET', `/v1/apps?filter[bundleId]=${encodeURIComponent(bundleId)}&limit=200`);
  const app = apps.data.find((a) => a.attributes.bundleId === bundleId);
  if (!app) {
    fail(
      `App Store Connect'te ${bundleId} için uygulama kaydı yok. App Store Connect > Uygulamalar > + > Yeni Uygulama ` +
        `ile iOS uygulaması oluşturun (Bundle ID: ${bundleId}), sonra iş akışını yeniden çalıştırın.`
    );
  }
  console.log(`✓ Uygulama kaydı bulundu: ${app.attributes.name} (${app.id})`);
  output('app_id', app.id);
}

async function nextBuildNumber(appId, atLeast) {
  let max = 0;
  let url = `/v1/builds?filter[app]=${appId}&limit=200&fields[builds]=version`;
  while (url) {
    const r = await api('GET', url);
    for (const b of r.data) {
      const n = parseInt(b.attributes.version, 10);
      if (Number.isFinite(n) && n > max) max = n;
    }
    url = r.links && r.links.next;
  }
  const next = Math.max(max + 1, parseInt(atLeast || '1', 10) || 1);
  console.log(`App Store Connect'teki en yüksek build numarası: ${max}; yeni: ${next}`);
  output('build_number', next);
}

const normSerial = (s) => String(s).toUpperCase().replace(/[^0-9A-F]/g, '').replace(/^0+/, '');

async function profile(serial, profileName) {
  const bundleId = env('BUNDLE_ID');
  const bid = await findBundleId(bundleId);
  if (!bid) fail(`Bundle ID ${bundleId} bulunamadı.`);

  const certs = await api('GET', '/v1/certificates?filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION&limit=200');
  const cert = certs.data.find((c) => normSerial(c.attributes.serialNumber) === normSerial(serial));
  if (!cert) {
    fail(
      `BUILD_CERTIFICATE_BASE64 içindeki sertifika (seri ${serial}) bu hesabın geçerli dağıtım sertifikaları arasında yok. ` +
        `Süresi dolmuş ya da iptal edilmiş olabilir.`
    );
  }
  console.log(`✓ Dağıtım sertifikası: ${cert.attributes.name} (${cert.id}), bitiş ${cert.attributes.expirationDate}`);

  // Capabilities the app's entitlements need (CAPABILITIES="GAME_CENTER,..."). Adding one makes old profiles stale.
  let capsChanged = false;
  const wanted = (process.env.CAPABILITIES || '').split(',').map((c) => c.trim()).filter(Boolean);
  if (wanted.length) {
    const have = await api('GET', `/v1/bundleIds/${bid.id}/bundleIdCapabilities`);
    const types = have.data.map((c) => c.attributes.capabilityType);
    for (const c of wanted) {
      if (types.includes(c)) { console.log(`✓ Yetenek açık: ${c}`); continue; }
      await api('POST', '/v1/bundleIdCapabilities', {
        data: { type: 'bundleIdCapabilities', attributes: { capabilityType: c },
          relationships: { bundleId: { data: { type: 'bundleIds', id: bid.id } } } },
      });
      console.log(`✓ Yetenek açıldı: ${c}`);
      capsChanged = true;
    }
  }

  const existing = await api(
    'GET',
    `/v1/profiles?filter[name]=${encodeURIComponent(profileName)}&filter[profileType]=IOS_APP_STORE&include=bundleId,certificates&limit=50`
  );
  let prof = existing.data.find((p) => {
    const certIds = ((p.relationships.certificates || {}).data || []).map((c) => c.id);
    const pBundle = ((p.relationships.bundleId || {}).data || {}).id;
    return !capsChanged && p.attributes.profileState === 'ACTIVE' && pBundle === bid.id && certIds.includes(cert.id);
  });

  if (prof) {
    console.log(`✓ Mevcut profil kullanılıyor: ${prof.attributes.name} (${prof.attributes.uuid})`);
  } else {
    for (const p of existing.data) {
      console.log(`Eski/uyumsuz profil siliniyor: ${p.attributes.name} (${p.id})`);
      await api('DELETE', `/v1/profiles/${p.id}`);
    }
    const r = await api('POST', '/v1/profiles', {
      data: {
        type: 'profiles',
        attributes: { name: profileName, profileType: 'IOS_APP_STORE' },
        relationships: {
          bundleId: { data: { type: 'bundleIds', id: bid.id } },
          certificates: { data: [{ type: 'certificates', id: cert.id }] },
        },
      },
    });
    prof = r.data;
    console.log(`✓ Yeni profil oluşturuldu: ${prof.attributes.name} (${prof.attributes.uuid})`);
  }

  const dirs = [
    path.join(os.homedir(), 'Library', 'MobileDevice', 'Provisioning Profiles'),
    path.join(os.homedir(), 'Library', 'Developer', 'Xcode', 'UserData', 'Provisioning Profiles'),
  ];
  const content = Buffer.from(prof.attributes.profileContent, 'base64');
  for (const d of dirs) {
    fs.mkdirSync(d, { recursive: true });
    fs.writeFileSync(path.join(d, `${prof.attributes.uuid}.mobileprovision`), content);
  }
  output('profile_name', prof.attributes.name);
  output('profile_uuid', prof.attributes.uuid);
}

const [cmd, ...args] = process.argv.slice(2);
const commands = {
  'ensure-app': () => ensureApp(),
  'next-build-number': () => nextBuildNumber(args[0], args[1]),
  profile: () => profile(args[0], args[1]),
};
if (!commands[cmd]) fail(`Bilinmeyen komut: ${cmd}`);
commands[cmd]().catch((e) => fail(e.message));

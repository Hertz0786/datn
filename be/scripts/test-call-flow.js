// End-to-end test of the call flow.
// Usage: node scripts/test-call-flow.js [usernameA] [passwordA] [usernameB] [passwordB]

const http = require('http');

const BASE = 'http://localhost:5000';

function request(method, path, body, token) {
  return new Promise((resolve, reject) => {
    const data = body ? JSON.stringify(body) : null;
    const url = new URL(BASE + path);
    const req = http.request(
      {
        hostname: url.hostname,
        port: url.port,
        path: url.pathname + url.search,
        method,
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: 'Bearer ' + token } : {}),
          ...(data ? { 'Content-Length': Buffer.byteLength(data) } : {}),
        },
      },
      (res) => {
        let chunks = '';
        res.on('data', (c) => (chunks += c));
        res.on('end', () => {
          let parsed;
          try {
            parsed = chunks ? JSON.parse(chunks) : {};
          } catch (e) {
            parsed = { raw: chunks };
          }
          resolve({ status: res.statusCode, body: parsed });
        });
      },
    );
    req.on('error', reject);
    if (data) req.write(data);
    req.end();
  });
}

function log(label, obj) {
  console.log('\n=== ' + label + ' ===');
  console.log(JSON.stringify(obj, null, 2));
}

async function login(username, password) {
  const res = await request('POST', '/api/auth/login', { username, password });
  if (res.status !== 200) {
    throw new Error(`Login failed for ${username}: ${res.status} ${JSON.stringify(res.body)}`);
  }
  return res.body;
}

async function ensureFriend(tokenA, userIdB) {
  // Try to send friend request and accept. If already friends, accept the 409.
  // First check friendship status.
  const status = await request('GET', '/api/friends/' + userIdB, null, tokenA);
  log('friendship status', status);
  if (status.body?.status === 'FRIENDS') {
    return 'already_friends';
  }
  if (status.body?.status === 'REQUEST_SENT') {
    return 'pending_self';
  }
  if (status.body?.status === 'REQUEST_RECEIVED') {
    // accept
    const accept = await request(
      'POST',
      '/api/friends/requests/' + (status.body?.requestId || '') + '/accept',
      null,
      tokenA,
    );
    log('accept request', accept);
    return 'accepted_inbound';
  }
  // Send a new request
  const send = await request(
    'POST',
    '/api/friends/requests',
    { targetUserId: userIdB, message: 'test' },
    tokenA,
  );
  log('send request', send);
  return 'sent';
}

async function main() {
  const args = process.argv.slice(2);
  const usernameA = args[0] || 'kid_alex';
  const passwordA = args[1] || 'Kiddo123!';
  const usernameB = args[2] || 'kid_bella';
  const passwordB = args[3] || 'Kiddo123!';

  console.log(`Testing call flow between "${usernameA}" and "${usernameB}"`);

  // 1. Login both
  const authA = await login(usernameA, passwordA);
  log('login A', { id: authA.user?.id, displayName: authA.user?.displayName });
  const authB = await login(usernameB, passwordB);
  log('login B', { id: authB.user?.id, displayName: authB.user?.displayName });

  const tokenA = authA.token;
  const tokenB = authB.token;
  const idA = authA.user.id;
  const idB = authB.user.id;

  // 2. Make sure they're friends (one direction is enough)
  try {
    await ensureFriend(tokenA, idB);
  } catch (e) {
    console.log('Friend setup error (continuing):', e.message);
  }

  // 3. A initiates a voice call to B
  const init = await request(
    'POST',
    '/api/calls/init',
    { calleeId: idB, callType: 'voice' },
    tokenA,
  );
  log('init call (A -> B voice)', init);
  if (init.status !== 200) {
    console.error('Init failed; aborting.');
    return;
  }
  const callId = init.body.callId;
  const channelName = init.body.channelName;
  const callerToken = init.body.token;
  const callerUid = init.body.uid;
  const appId = init.body.appId;
  console.log('callId:', callId);
  console.log('channelName:', channelName);
  console.log('appId:', appId);
  console.log('callerUid:', callerUid);
  console.log('callerToken length:', callerToken.length);

  // 4. B accepts the call
  const accept = await request('POST', '/api/calls/' + callId + '/accept', null, tokenB);
  log('B accepts', accept);
  if (accept.status !== 200) {
    console.error('Accept failed; aborting.');
    return;
  }
  console.log('calleeToken length:', accept.body.token.length);
  console.log('calleeUid:', accept.body.uid);

  // 5. B ends the call
  const end = await request('POST', '/api/calls/' + callId + '/end', null, tokenB);
  log('B ends call', end);

  // 6. Check history
  const hist = await request('GET', '/api/calls/history?limit=5', null, tokenA);
  log('A history', hist);
  const histB = await request('GET', '/api/calls/history?limit=5', null, tokenB);
  log('B history', histB);

  // 7. Test VIDEO call
  console.log('\n--- Testing video call ---');
  const videoInit = await request(
    'POST',
    '/api/calls/init',
    { calleeId: idB, callType: 'video' },
    tokenA,
  );
  log('init video call', videoInit);
  if (videoInit.status === 200) {
    const videoCallId = videoInit.body.callId;
    const videoAccept = await request('POST', '/api/calls/' + videoCallId + '/accept', null, tokenB);
    log('B accepts video', videoAccept);
    const videoEnd = await request('POST', '/api/calls/' + videoCallId + '/end', null, tokenA);
    log('A ends video', videoEnd);
  }

  // 8. Test settings GET/PATCH
  const settingsGet = await request('GET', '/api/calls/settings', null, tokenA);
  log('A settings (default)', settingsGet);
  const settingsPatch = await request(
    'PATCH',
    '/api/calls/settings',
    { whoCanCall: 'everyone', maxCallDurationSeconds: 1800 },
    tokenA,
  );
  log('A settings (updated)', settingsPatch);

  // 9. Test reject flow
  console.log('\n--- Testing reject flow ---');
  const rejectInit = await request(
    'POST',
    '/api/calls/init',
    { calleeId: idB, callType: 'voice' },
    tokenA,
  );
  log('init for reject', rejectInit);
  if (rejectInit.status === 200) {
    const rejectCallId = rejectInit.body.callId;
    const reject = await request('POST', '/api/calls/' + rejectCallId + '/reject', null, tokenB);
    log('B rejects', reject);
  }

  // 10. Test call non-friend (should fail with 403)
  console.log('\n--- Testing call non-friend (expect 403/404) ---');
  // Try to register a new user
  const newUsername = 'call_test_' + Date.now();
  const reg = await request('POST', '/api/auth/register', {
    displayName: 'Test User',
    username: newUsername,
    age: 12,
    password: 'Test1234!',
  });
  if (reg.status === 200 || reg.status === 201) {
    log('register new user', { id: reg.body.user?.id, status: reg.status });
    const newToken = reg.body.token;
    const newId = reg.body.user.id;
    const callNonFriend = await request(
      'POST',
      '/api/calls/init',
      { calleeId: newId, callType: 'voice' },
      tokenA,
    );
    log('A calls non-friend (should fail)', callNonFriend);
    const acceptNonFriend = await request(
      'POST',
      '/api/calls/init',
      { calleeId: idA, callType: 'voice' },
      newToken,
    );
    log('non-friend calls A (should fail)', acceptNonFriend);
  } else {
    log('register failed', reg);
  }

  console.log('\n=== All test steps complete ===');
}

main().catch((err) => {
  console.error('Test failed:', err);
  process.exit(1);
});

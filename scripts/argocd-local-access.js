const listenPort = Bun.env.ARGOCD_LOCAL_PORT || '8086';
const sshHost = Bun.env.ARGOCD_SSH_HOST || 'medha-master';

if (!/^\d+$/.test(listenPort)) {
  console.error('ARGOCD_LOCAL_PORT must be numeric');
  process.exit(1);
}

if (!Bun.which('ssh')) {
  console.error('ssh is required');
  process.exit(1);
}

// Clean up local process(es) using the listenPort
const localLsof = Bun.spawnSync(['lsof', '-t', `-i:${listenPort}`]);
if (localLsof.status === 0) {
  const localPids = localLsof.stdout.toString().trim().split('\n').filter(Boolean);
  if (localPids.length > 0) {
    console.log(`Killing local process(es) on port ${listenPort}: ${localPids.join(', ')}`);
    Bun.spawnSync(['kill', '-9', ...localPids]);
  }
}

// Clean up remote process(es) using the listenPort or matching port-forward pattern
console.log(`Cleaning up existing remote port-forwards on ${sshHost}...`);
const cleanupCmd = `pid=\$(lsof -t -i:${listenPort}) && [ -n "\$pid" ] && kill -9 \$pid; pkill -f "kubectl.*port-forward.*argocd-server" || true`;
const cleanup = Bun.spawn([
  'ssh',
  sshHost,
  cleanupCmd
]);
await cleanup.exited;

console.log(`Argo CD will be available at http://127.0.0.1:${listenPort}`);
console.log('Keep this process running; press Ctrl-C to close access.');

const child = Bun.spawn([
  'ssh',
  '-o', 'ExitOnForwardFailure=yes',
  '-L', `${listenPort}:127.0.0.1:${listenPort}`,
  sshHost,
  `kubectl --namespace argocd port-forward --address 127.0.0.1 service/argocd-server '${listenPort}:80'`
], {
  stdout: 'inherit',
  stderr: 'inherit',
  stdin: 'inherit'
});

const exitCode = await child.exited;
process.exit(exitCode);

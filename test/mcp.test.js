import assert from 'node:assert/strict';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StdioClientTransport } from '@modelcontextprotocol/sdk/client/stdio.js';

test('stdio exposes editing tools and rejects malformed RAPID before controller access', async () => {
  const client = new Client({ name: 'compatibility-check', version: '1.0.0' });
  try {
    await client.connect(new StdioClientTransport({
      command: process.execPath,
      args: [fileURLToPath(new URL('../dist/index.js', import.meta.url))],
    }));
    const { tools } = await client.listTools();
    for (const name of ['rs_ping', 'rs_write_module', 'rws_write_module']) {
      assert.ok(tools.some(tool => tool.name === name), name);
    }
    const result = await client.callTool({
      name: 'rs_write_module',
      arguments: { task: 'T_ROB1', module: 'Broken', code: 'MODULE Broken\nPROC main()\nENDMODULE' },
    });
    assert.equal(result.isError, true);
    assert.match(JSON.stringify(result), /validation failed/i);
  } finally {
    await client.close();
  }
});

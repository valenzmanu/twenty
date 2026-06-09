#!/usr/bin/env node
const fs = require('node:fs');
const crypto = require('node:crypto');

const envFile = '.env';
const bootstrapFile = 'admin-bootstrap.txt';
const endpoint = 'http://127.0.0.1:3000/graphql';

const env = Object.fromEntries(
  fs
    .readFileSync(envFile, 'utf8')
    .split(/\r?\n/)
    .filter((line) => line && !line.startsWith('#') && line.includes('='))
    .map((line) => {
      const index = line.indexOf('=');
      return [line.slice(0, index), line.slice(index + 1)];
    }),
);

const email = env.TWENTY_ADMIN_EMAIL || 'mantt89.mv@gmail.com';

function getOrCreatePassword() {
  if (fs.existsSync(bootstrapFile)) {
    const match = fs.readFileSync(bootstrapFile, 'utf8').match(/^password=(.+)$/m);
    if (match) return match[1];
  }

  const password = `Ib-${crypto.randomBytes(18).toString('base64url')}`;
  const content = [
    `email=${email}`,
    `password=${password}`,
    `url=${env.SERVER_URL || 'https://crm.instabloom.gt'}`,
    `created_at=${new Date().toISOString()}`,
    '',
  ].join('\n');

  fs.writeFileSync(bootstrapFile, content, { mode: 0o600 });
  return password;
}

async function gql(query, variables, token) {
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ query, variables }),
  });

  const json = await response.json();
  if (!response.ok || json.errors) {
    const message = JSON.stringify(json.errors || json);
    const error = new Error(message);
    error.payload = json;
    throw error;
  }
  return json.data;
}

async function main() {
  const password = getOrCreatePassword();

  const signUpMutation = `
    mutation SignUp($email: String!, $password: String!) {
      signUp(email: $email, password: $password) {
        tokens {
          accessOrWorkspaceAgnosticToken {
            token
            expiresAt
          }
        }
      }
    }
  `;

  const workspaceMutation = `
    mutation SignUpInNewWorkspace {
      signUpInNewWorkspace {
        workspace {
          id
          workspaceUrls {
            subdomainUrl
            customUrl
          }
        }
        loginToken {
          token
          expiresAt
        }
      }
    }
  `;

  let token;
  try {
    const signUpData = await gql(signUpMutation, { email, password });
    token = signUpData.signUp.tokens.accessOrWorkspaceAgnosticToken.token;
  } catch (error) {
    const message = String(error.message || '');
    if (message.includes('already') || message.includes('USER')) {
      console.log(`Admin user ${email} already exists. Bootstrap skipped.`);
      return;
    }
    throw error;
  }

  const workspaceData = await gql(workspaceMutation, {}, token);
  const workspace = workspaceData.signUpInNewWorkspace.workspace;
  fs.appendFileSync(
    bootstrapFile,
    [
      `workspace_id=${workspace.id}`,
      `workspace_url=${workspace.workspaceUrls.customUrl || workspace.workspaceUrls.subdomainUrl}`,
      `bootstrapped_at=${new Date().toISOString()}`,
      '',
    ].join('\n'),
  );

  console.log(`Bootstrapped admin workspace for ${email}.`);
}

main().catch((error) => {
  console.error(error.message || error);
  process.exit(1);
});

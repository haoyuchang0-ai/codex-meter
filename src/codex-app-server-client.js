const { spawn } = require("node:child_process");
const readline = require("node:readline");

const DEFAULT_CODEX_CLI = "/Applications/Codex.app/Contents/Resources/codex";

class CodexAppServerClient {
  constructor(options = {}) {
    this.codexCli = options.codexCli || process.env.CODEX_CLI || DEFAULT_CODEX_CLI;
    this.requestTimeoutMs = options.requestTimeoutMs || 15000;
    this.process = null;
    this.pending = new Map();
    this.nextId = 1;
    this.readyPromise = null;
    this.lastStderr = "";
  }

  async request(method, params) {
    await this.ensureReady();
    return this.sendRequest(method, params);
  }

  async ensureReady() {
    if (this.readyPromise) {
      return this.readyPromise;
    }

    this.startProcess();
    this.readyPromise = this.sendRequest("initialize", {
      clientInfo: {
        name: "codex-quota-window",
        title: "Codex Quota Window",
        version: "0.1.0",
      },
      capabilities: {
        experimentalApi: true,
      },
    }).then(() => {
      this.writeMessage({ method: "initialized" });
    });

    return this.readyPromise;
  }

  startProcess() {
    if (this.process) {
      return;
    }

    this.process = spawn(this.codexCli, ["app-server", "--stdio"], {
      stdio: ["pipe", "pipe", "pipe"],
    });

    const stdout = readline.createInterface({
      input: this.process.stdout,
      crlfDelay: Infinity,
    });

    stdout.on("line", (line) => {
      this.handleLine(line);
    });

    this.process.stderr.on("data", (chunk) => {
      this.lastStderr = `${this.lastStderr}${chunk.toString()}`.slice(-4000);
    });

    this.process.on("error", (error) => {
      this.rejectAll(error);
      this.readyPromise = null;
      this.process = null;
    });

    this.process.on("exit", (code, signal) => {
      const detail = signal ? `signal ${signal}` : `code ${code}`;
      const error = new Error(`Codex app-server exited with ${detail}`);
      if (this.lastStderr.trim()) {
        error.details = this.lastStderr.trim();
      }
      this.rejectAll(error);
      this.readyPromise = null;
      this.process = null;
    });
  }

  handleLine(line) {
    let message;
    try {
      message = JSON.parse(line);
    } catch {
      return;
    }

    if (!Object.prototype.hasOwnProperty.call(message, "id")) {
      return;
    }

    const pending = this.pending.get(message.id);
    if (!pending) {
      return;
    }

    this.pending.delete(message.id);
    clearTimeout(pending.timeout);

    if (message.error) {
      const error = new Error(message.error.message || "Codex app-server error");
      error.code = message.error.code;
      pending.reject(error);
      return;
    }

    pending.resolve(message.result);
  }

  sendRequest(method, params) {
    const id = this.nextId++;
    const message = { id, method };
    if (params !== undefined) {
      message.params = params;
    }

    return new Promise((resolve, reject) => {
      const timeout = setTimeout(() => {
        this.pending.delete(id);
        reject(new Error(`Timed out waiting for ${method}`));
      }, this.requestTimeoutMs);

      this.pending.set(id, { resolve, reject, timeout });

      try {
        this.writeMessage(message);
      } catch (error) {
        clearTimeout(timeout);
        this.pending.delete(id);
        reject(error);
      }
    });
  }

  writeMessage(message) {
    if (!this.process || !this.process.stdin.writable) {
      throw new Error("Codex app-server is not running");
    }

    this.process.stdin.write(`${JSON.stringify(message)}\n`);
  }

  rejectAll(error) {
    for (const [id, pending] of this.pending.entries()) {
      clearTimeout(pending.timeout);
      pending.reject(error);
      this.pending.delete(id);
    }
  }

  close() {
    if (this.process) {
      this.process.kill();
      this.process = null;
    }
  }
}

module.exports = {
  CodexAppServerClient,
};

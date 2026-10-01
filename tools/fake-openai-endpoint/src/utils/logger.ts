export interface LogPayload {
  requestId?: string;
  method?: string;
  url?: string;
  status?: number;
  durationMs?: number;
  model?: string;
  stream?: boolean;
  chunks?: number;
  bytes?: number;
  error?: string;
}

export const logger = {
  info(message: string, meta?: Record<string, unknown> | LogPayload) {
    const timestamp = new Date().toISOString();
    if (meta) {
      console.log(`[${timestamp}] [INFO] ${message}`, JSON.stringify(meta));
    } else {
      console.log(`[${timestamp}] [INFO] ${message}`);
    }
  },

  warn(message: string, meta?: Record<string, unknown> | LogPayload) {
    const timestamp = new Date().toISOString();
    if (meta) {
      console.warn(`[${timestamp}] [WARN] ${message}`, JSON.stringify(meta));
    } else {
      console.warn(`[${timestamp}] [WARN] ${message}`);
    }
  },

  error(message: string, meta?: Record<string, unknown> | LogPayload) {
    const timestamp = new Date().toISOString();
    if (meta) {
      console.error(`[${timestamp}] [ERROR] ${message}`, JSON.stringify(meta));
    } else {
      console.error(`[${timestamp}] [ERROR] ${message}`);
    }
  },

  debug(message: string, meta?: Record<string, unknown> | LogPayload) {
    if (process.env.LOG_LEVEL === 'debug') {
      const timestamp = new Date().toISOString();
      if (meta) {
        console.debug(`[${timestamp}] [DEBUG] ${message}`, JSON.stringify(meta));
      } else {
        console.debug(`[${timestamp}] [DEBUG] ${message}`);
      }
    }
  },
};

/**
 * HTTP 网络工具 — ArkTS 版 fetch 替代
 * 使用 @ohos.net.http 封装 fetch 式 API
 */
import { http } from '@kit.NetworkKit';

/** 简化的 fetch 响应 */
class FetchResponse {
  private _body: string;
  private _status: number;
  private _ok: boolean;

  constructor(body: string, status: number) {
    this._body = body;
    this._status = status;
    this._ok = status >= 200 && status < 300;
  }

  get ok(): boolean { return this._ok; }
  get status(): number { return this._status; }

  async json(): Promise<Object> {
    return JSON.parse(this._body) as Object;
  }

  async text(): Promise<string> {
    return this._body;
  }
}

/**
 * fetch 替代 — GET 请求
 * @param url 请求地址
 * @param headers 可选请求头（如 BMCLAPI 的 x-bmclapi-hash 校验头）
 * @param timeoutMs 超时（毫秒），默认 15s
 */
export async function httpGet(url: string, headers?: Record<string, string>,
  timeoutMs: number = 15000): Promise<FetchResponse> {
  const req = http.createHttp();
  try {
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs
    };
    if (headers !== undefined) {
      options.header = headers;
    }
    const resp = await req.request(url, options);
    return new FetchResponse(resp.result as string ?? '', resp.responseCode);
  } finally {
    req.destroy();
  }
}

/**
 * fetch 替代 — POST 请求
 */
export async function httpPost(url: string, body: string): Promise<FetchResponse> {
  const req = http.createHttp();
  try {
    const resp = await req.request(url, {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' },
      extraData: body,
      connectTimeout: 15000,
      readTimeout: 30000
    });
    return new FetchResponse(resp.result as string ?? '', resp.responseCode);
  } finally {
    req.destroy();
  }
}

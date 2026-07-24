/**
 * HTTP 网络工具 — ArkTS 版 fetch 替代
 * 使用 @ohos.net.http 封装 fetch 式 API
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';

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

  async json(): Promise<Record<string, Object>> {
    return JSON.parse(this._body) as Record<string, Object>;
  }

  async text(): Promise<string> {
    return this._body;
  }
}

/**
 * fetch 替代 — GET 请求
 */
export async function httpGet(url: string): Promise<FetchResponse> {
  const req = http.createHttp();
  try {
    const resp = await req.request(url, {
      method: http.RequestMethod.GET,
      connectTimeout: 15000,
      readTimeout: 30000
    });
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

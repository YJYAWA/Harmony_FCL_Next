/**
 * Microsoft OAuth 账号 - 完整认证流程
 * 移植自: FCLCore/auth/OAuth.java + OAuthAccount.java
 *
 * 认证链路:
 *   Microsoft OAuth 2.0 (Device Code Flow)
 *   → Xbox Live 认证 (XBL)
 *   → Xbox Security Token Service (XSTS)
 *   → Minecraft 认证
 *   → Minecraft 角色信息获取
 */
import {
  Account, AuthInfo, CharacterInfo, AccountType,
  AuthenticationException, CredentialExpiredException,
  ServerDisconnectException, ServerResponseMalformedException,
  NoCharacterException
} from './AuthTypes';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { uuidv4 } from '../util/UUIDUtils';
import { Constants } from '../util/Constants';

const TAG = 'FCL-MicrosoftAccount';

/** OAuth 配置 */
interface OAuthConfig {
  authorizationURL: string;
  accessTokenURL: string;
  deviceCodeURL: string;
  tokenURL: string;
  clientId: string;
  scope: string;
}

/** 设备码响应 */
interface DeviceCodeResponse {
  user_code: string;
  device_code: string;
  verification_uri: string;
  expires_in: number;
  interval: number;
  message?: string;
  error?: string;
  error_description?: string;
}

/** Token 响应 */
interface TokenResponse {
  token_type?: string;
  expires_in?: number;
  access_token?: string;
  refresh_token?: string;
  error?: string;
  error_description?: string;
}

/** Xbox Live 认证响应 */
interface XBLResponse {
  Token: string;
  DisplayClaims: {
    xui: Array<{ uhs: string }>;
  };
}

/** XSTS 认证响应 */
interface XSTSResponse {
  Token: string;
  DisplayClaims: {
    xui: Array<{ uhs: string }>;
  };
}

/** Minecraft 认证响应 */
interface MinecraftAuthResponse {
  access_token: string;
  token_type: string;
  expires_in: number;
}

/** Minecraft 角色信息 */
interface MinecraftProfileResponse {
  id: string;
  name: string;
  skins?: Array<{
    url: string;
    variant: string;
  }>;
  capes?: Array<{
    url: string;
  }>;
}

/** 存储格式 */
interface MicrosoftAccountStorage {
  type: string;
  username: string;
  uuid: string;
  refreshToken: string;
  msAccessToken: string;
  msRefreshToken: string;
  lastLoginTime: number;
}

/**
 * Microsoft 正版账号
 */
export class MicrosoftAccount implements Account {
  readonly type: AccountType = AccountType.MICROSOFT;

  private _username: string = '';
  private _uuid: string = '';
  private _character: string = '';
  private msAccessToken: string = '';
  private msRefreshToken: string = '';
  private _refreshToken: string = '';
  private lastLoginTime: number = 0;
  private isLoggedIn: boolean = false;

  // OAuth 配置
  private readonly oauthConfig: OAuthConfig = {
    authorizationURL: 'https://login.live.com/oauth20_authorize.srf',
    accessTokenURL: 'https://login.live.com/oauth20_token.srf',
    deviceCodeURL: 'https://login.microsoftonline.com/consumers/oauth2/v2.0/devicecode',
    tokenURL: 'https://login.microsoftonline.com/consumers/oauth2/v2.0/token',
    clientId: Constants.MICROSOFT_CLIENT_ID,
    scope: 'XboxLive.signin offline_access'
  };

  /** 状态回调 (UI 层注册) */
  statusCallback?: (status: string) => void;

  constructor(refreshToken?: string) {
    if (refreshToken) {
      this._refreshToken = refreshToken;
    }
  }

  get username(): string { return this._username; }
  get character(): string { return this._character; }
  get uuid(): string { return this._uuid; }
  get identifier(): string { return `microsoft:${this._uuid}`; }
  get refreshToken(): string { return this._refreshToken; }

  /**
   * 完整登录流程 (Device Code Flow)
   */
  async logIn(): Promise<AuthInfo> {
    try {
      // 如果有 refresh token, 尝试刷新
      if (this._refreshToken) {
        try {
          return await this.refreshTokens();
        } catch (err) {
          if (err instanceof CredentialExpiredException) {
            // 凭证过期, 继续走完整登录
          } else {
            throw err;
          }
        }
      }

      // Step 1: 获取设备码
      this.updateStatus('正在获取设备码...');
      const deviceCode = await this.requestDeviceCode();

      // 通知用户去浏览器输入验证码
      this.updateStatus(`请在浏览器中打开 ${deviceCode.verification_uri} 并输入代码: ${deviceCode.user_code}`);

      // Step 2: 轮询 Token
      const msToken = await this.pollForToken(deviceCode);

      // Step 3: Xbox Live 认证
      this.updateStatus('正在登录 Xbox Live...');
      const xblToken = await this.authenticateXBL(msToken.access_token!);

      // Step 4: XSTS 认证
      this.updateStatus('正在验证 Xbox 安全令牌...');
      const xstsToken = await this.authenticateXSTS(xblToken.Token);

      // Step 5: Minecraft 认证
      this.updateStatus('正在登录 Minecraft...');
      const mcToken = await this.authenticateMinecraft(xstsToken);

      // Step 6: 获取角色信息
      this.updateStatus('正在获取角色信息...');
      const profile = await this.getMinecraftProfile(mcToken.access_token);

      // 保存状态
      this._username = profile.name;
      this._uuid = profile.id;
      this._character = profile.name;
      this.msAccessToken = msToken.access_token!;
      this.msRefreshToken = msToken.refresh_token ?? '';
      this._refreshToken = mcToken.access_token;
      this.lastLoginTime = Date.now();
      this.isLoggedIn = true;

      this.updateStatus(`登录成功: ${profile.name}`);

      return new AuthInfo(
        profile.name,
        profile.id,
        mcToken.access_token,
        'msa',
        {}
      );

    } catch (err) {
      this.isLoggedIn = false;
      throw this.wrapError(err);
    }
  }

  /**
   * 刷新所有 Token
   */
  private async refreshTokens(): Promise<AuthInfo> {
    // 刷新 Microsoft Token
    const response = await this.httpPostJSON<TokenResponse>(
      this.oauthConfig.tokenURL,
      {
        client_id: this.oauthConfig.clientId,
        refresh_token: this._refreshToken,
        grant_type: 'refresh_token',
        scope: this.oauthConfig.scope
      }
    );

    if (response.error) {
      throw new CredentialExpiredException(response.error_description ?? 'Refresh token expired');
    }

    this.msAccessToken = response.access_token!;
    if (response.refresh_token) {
      this.msRefreshToken = response.refresh_token;
    }

    // 获取角色信息
    const profile = await this.getMinecraftProfile(this.msAccessToken);

    return new AuthInfo(profile.name, profile.id, this.msAccessToken, 'msa', {});
  }

  /** 请求设备码 */
  private async requestDeviceCode(): Promise<DeviceCodeResponse> {
    const response = await this.httpPostJSON<DeviceCodeResponse>(
      this.oauthConfig.deviceCodeURL,
      {
        client_id: this.oauthConfig.clientId,
        scope: this.oauthConfig.scope
      }
    );

    if (response.error) {
      throw new AuthenticationException(
        `Failed to get device code: ${response.error_description ?? response.error}`
      );
    }

    return response;
  }

  /** 轮询等待用户完成认证 */
  private async pollForToken(deviceCode: DeviceCodeResponse): Promise<TokenResponse> {
    const startTime = Date.now();
    let interval = deviceCode.interval * 1000;
    const maxWait = Math.min(deviceCode.expires_in, 900) * 1000; // 最多等 15 分钟

    while (Date.now() - startTime < maxWait) {
      await this.sleep(Math.max(interval, 1000));

      const response = await this.httpPostJSON<TokenResponse>(
        this.oauthConfig.tokenURL,
        {
          grant_type: 'urn:ietf:params:oauth:grant-type:device_code',
          code: deviceCode.device_code,
          client_id: this.oauthConfig.clientId
        }
      );

      if (response.access_token) {
        return response;
      }

      if (response.error === 'authorization_pending') {
        continue; // 用户还没操作, 继续等
      }

      if (response.error === 'slow_down') {
        interval += 5000;
        continue;
      }

      if (response.error === 'expired_token') {
        throw new NoCharacterException('Device code expired');
      }

      throw new AuthenticationException(
        `Token polling error: ${response.error} - ${response.error_description ?? ''}`
      );
    }

    throw new NoCharacterException('Authentication timed out');
  }

  /**
   * Xbox Live 认证
   * POST https://user.auth.xboxlive.com/user/authenticate
   */
  private async authenticateXBL(accessToken: string): Promise<XBLResponse> {
    const body = {
      Properties: {
        AuthMethod: 'RPS',
        SiteName: 'user.auth.xboxlive.com',
        RpsTicket: `d=${accessToken}`
      },
      RelyingParty: 'http://auth.xboxlive.com',
      TokenType: 'JWT'
    };

    const response = await this.httpPostJSON<XBLResponse>(
      Constants.XBOX_AUTH_URL,
      body,
      { 'x-xbl-contract-version': '1' }
    );

    if (!response.Token) {
      throw new AuthenticationException('Xbox Live authentication failed: no token');
    }

    return response;
  }

  /**
   * XSTS 认证
   * POST https://xsts.auth.xboxlive.com/xsts/authorize
   */
  private async authenticateXSTS(xblToken: string): Promise<XSTSResponse> {
    const body = {
      Properties: {
        SandboxId: 'RETAIL',
        UserTokens: [xblToken]
      },
      RelyingParty: 'rp://api.minecraftservices.com/',
      TokenType: 'JWT'
    };

    const response = await this.httpPostJSON<XSTSResponse>(
      Constants.XSTS_AUTH_URL,
      body,
      { 'x-xbl-contract-version': '1' }
    );

    // 检查 XSTS 错误码
    if (!response.Token) {
      throw new AuthenticationException(
        'XSTS authentication failed. This may indicate the account does not own Minecraft.'
      );
    }

    return response;
  }

  /**
   * Minecraft 认证
   * POST https://api.minecraftservices.com/authentication/login_with_xbox
   */
  private async authenticateMinecraft(xstsToken: XSTSResponse): Promise<MinecraftAuthResponse> {
    const uhs = xstsToken.DisplayClaims.xui[0]?.uhs;
    if (!uhs) {
      throw new AuthenticationException('Missing user hash in XSTS response');
    }

    const body = {
      identityToken: `XBL3.0 x=${uhs};${xstsToken.Token}`
    };

    const response = await this.httpPostJSON<MinecraftAuthResponse>(
      `${Constants.MOJANG_API_URL}/authentication/login_with_xbox`,
      body
    );

    if (!response.access_token) {
      throw new AuthenticationException('Minecraft authentication failed');
    }

    return response;
  }

  /**
   * 获取 Minecraft 角色信息
   * GET https://api.minecraftservices.com/minecraft/profile
   */
  private async getMinecraftProfile(mcToken: string): Promise<MinecraftProfileResponse> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(
        `${Constants.MOJANG_API_URL}/minecraft/profile`,
        {
          method: http.RequestMethod.GET,
          header: {
            'Authorization': `Bearer ${mcToken}`,
            'Content-Type': 'application/json'
          }
        }
      );

      if (response.responseCode !== 200) {
        // 404 可能意味着没有角色
        if (response.responseCode === 404) {
          throw new NoCharacterException(
            'No Minecraft character found. Please purchase Minecraft Java Edition and create a character.'
          );
        }
        throw new ServerResponseMalformedException(`HTTP ${response.responseCode}`);
      }

      const profile = JSON.parse(response.result as string) as MinecraftProfileResponse;

      if (!profile.id || !profile.name) {
        throw new ServerResponseMalformedException('Invalid profile response');
      }

      return profile;

    } finally {
      httpRequest.destroy();
    }
  }

  /** 离线模式 */
  async playOffline(): Promise<AuthInfo> {
    if (!this._username) {
      throw new AuthenticationException('Must login online at least once first');
    }
    return new AuthInfo(this._username, this._uuid, 'offline-token', 'msa');
  }

  /** 序列化 */
  toStorage(): MicrosoftAccountStorage {
    return {
      type: AccountType.MICROSOFT,
      username: this._username,
      uuid: this._uuid,
      refreshToken: this._refreshToken,
      msAccessToken: this.msAccessToken,
      msRefreshToken: this.msRefreshToken,
      lastLoginTime: this.lastLoginTime
    };
  }

  clearCache(): void {
    this.msAccessToken = '';
    this.msRefreshToken = '';
  }

  /** 从存储恢复 */
  static fromStorage(data: Record<string, Object>): MicrosoftAccount {
    const account = new MicrosoftAccount();
    account._username = (data['username'] as string) ?? '';
    account._uuid = (data['uuid'] as string) ?? '';
    account._character = account._username;
    account._refreshToken = (data['refreshToken'] as string) ?? '';
    account.msAccessToken = (data['msAccessToken'] as string) ?? '';
    account.msRefreshToken = (data['msRefreshToken'] as string) ?? '';
    account.lastLoginTime = (data['lastLoginTime'] as number) ?? 0;
    return account;
  }

  // ========== 工具方法 ==========

  private async httpPostJSON<T>(url: string, body: Object, extraHeaders?: Record<string, string>):
    Promise<T> {
    const httpRequest = http.createHttp();
    try {
      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...extraHeaders
      };

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: headers,
        extraData: JSON.stringify(body),
        connectTimeout: 10000,
        readTimeout: 30000
      });

      if (response.result) {
        return JSON.parse(response.result as string) as T;
      }
      return {} as T;
    } catch (err) {
      const error = err as BusinessError;
      throw new ServerDisconnectException(`HTTP request failed: ${error.message}`);
    } finally {
      httpRequest.destroy();
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  private updateStatus(status: string): void {
    hilog.info(0x0000, TAG, status);
    if (this.statusCallback) {
      this.statusCallback(status);
    }
  }

  private wrapError(err: Error): AuthenticationException {
    if (err instanceof AuthenticationException) {
      return err;
    }
    return new AuthenticationException(err.message, err);
  }

  /** 检查是否已登录 */
  get loggedIn(): boolean {
    return this.isLoggedIn && this._uuid.length > 0;
  }

  /** Token 是否可能已过期 (超过 12 小时) */
  get tokenExpired(): boolean {
    return Date.now() - this.lastLoginTime > 12 * 60 * 60 * 1000;
  }
}

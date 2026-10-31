/**
 * Yggdrasil / Authlib-Injector 第三方认证
 * 移植自: FCLCore/auth/yggdrasil/
 *
 * 支持:
 * - 外置登录 (authlib-injector)
 * - LittleSkin / Blessing Skin 等皮肤站
 * - 自定义 Yggdrasil API 服务器
 */
import {
  Account, AuthInfo, AccountType,
  AuthenticationException, ServerDisconnectException,
  ServerResponseMalformedException
} from './AuthTypes';
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { uuidv4 } from '../util/UUIDUtils';

const TAG = 'FCL-YggdrasilAccount';

/** Yggdrasil 服务器配置 */
export interface YggdrasilServer {
  /** 服务器名称 */
  name: string;
  /** API 根 URL */
  apiRoot: string;
  /** 皮肤域名 */
  skinDomain?: string;
  /** 注册链接 */
  registerUrl?: string;
}

/** Yggdrasil 认证代理 (agent) */
interface YggdrasilAgent {
  name: string;
  version: number;
}

/** 角色基本信息 */
export interface ProfileInfo {
  id: string;
  name: string;
}

/** 用户属性键值对 */
export interface UserProperty {
  name: string;
  value: string;
}

/** 用户信息 */
export interface UserInfo {
  id: string;
  properties: UserProperty[];
}

/** Yggdrasil 登录请求 */
interface YggdrasilAuthRequest {
  agent: YggdrasilAgent;
  username: string;
  password: string;
  clientToken: string;
  requestUser: boolean;
}

/** Yggdrasil 登录响应 */
interface YggdrasilAuthResponse {
  accessToken: string;
  clientToken: string;
  availableProfiles: ProfileInfo[];
  selectedProfile?: ProfileInfo;
  user?: UserInfo;
  error?: string;
  errorMessage?: string;
}

/** Yggdrasil 刷新响应 */
interface YggdrasilRefreshResponse {
  accessToken: string;
  clientToken: string;
  selectedProfile: ProfileInfo;
  error?: string;
  errorMessage?: string;
}

/** Yggdrasil Token 请求体 (refresh / validate / invalidate) */
interface YggdrasilTokenRequest {
  accessToken: string;
  clientToken: string;
  requestUser?: boolean;
}

/** 存储格式 */
interface YggdrasilStorage {
  type: string;
  serverName: string;
  apiRoot: string;
  username: string;
  uuid: string;
  character: string;
  accessToken: string;
  clientToken: string;
}

/**
 * Yggdrasil 外置登录账号
 */
export class YggdrasilAccount implements Account {
  readonly type: AccountType = AccountType.YGGDRASIL;

  private _username: string = '';
  private _password: string = '';
  private _character: string = '';
  private _uuid: string = '';
  private accessToken: string = '';
  private clientToken: string = '';
  private serverConfig: YggdrasilServer;

  statusCallback?: (status: string) => void;

  constructor(server: YggdrasilServer, username?: string, password?: string) {
    this.serverConfig = server;
    if (username) {
      this._username = username;
    }
    if (password) {
      this._password = password;
    }
  }

  get username(): string { return this._username; }
  get character(): string { return this._character; }
  get uuid(): string { return this._uuid; }
  get identifier(): string { return `yggdrasil:${this.serverConfig.name}:${this._username}`; }

  setUsername(name: string): void { this._username = name; }
  setPassword(pwd: string): void { this._password = pwd; }
  setServer(server: YggdrasilServer): void { this.serverConfig = server; }

  /**
   * 登录到 Yggdrasil 认证服务器
   */
  async logIn(): Promise<AuthInfo> {
    if (!this._username || !this._password) {
      throw new AuthenticationException('Username and password are required');
    }

    // 尝试刷新现有 Token
    if (this.accessToken && this.clientToken) {
      try {
        return await this.refresh();
      } catch {
        // 刷新失败, 走完整登录
      }
    }

    this.updateStatus('Logging in...');

    // 生成 clientToken
    if (!this.clientToken) {
      this.clientToken = uuidv4();
    }

    const authRequest: YggdrasilAuthRequest = {
      agent: {
        name: 'Minecraft',
        version: 1
      },
      username: this._username,
      password: this._password,
      clientToken: this.clientToken,
      requestUser: true
    };

    const response = await this.httpPostJSON<YggdrasilAuthResponse>(
      `${this.serverConfig.apiRoot}/authserver/authenticate`,
      authRequest
    );

    // 检查错误响应
    if (response.error) {
      throw new AuthenticationException(
        `Authentication failed: ${response.errorMessage ?? response.error}`
      );
    }

    // 选择角色
    const profile = response.selectedProfile;
    if (!profile && response.availableProfiles && response.availableProfiles.length > 0) {
      // 自动选择第一个角色
      const firstProfile = response.availableProfiles[0];
      return await this.selectProfile(firstProfile.id, response.accessToken);
    }

    if (!profile) {
      throw new AuthenticationException('No character available on this account');
    }

    this.accessToken = response.accessToken;
    this._character = profile.name;
    this._uuid = profile.id;

    this.updateStatus(`Logged in as ${profile.name}`);

    return new AuthInfo(profile.name, profile.id, response.accessToken, 'yggdrasil');
  }

  /**
   * 选择角色
   */
  private async selectProfile(profileId: string, accessToken: string): Promise<AuthInfo> {
    // Yggdrasil 协议: 选择角色会返回新的 token
    // 简化实现: 直接使用第一个角色的信息
    this.accessToken = accessToken;
    this._uuid = profileId;

    // 通过 profile API 获取角色名
    try {
      const profile = await this.getProfile(profileId);
      this._character = profile;
    } catch {
      this._character = 'Unknown';
    }

    return new AuthInfo(this._character, this._uuid, this.accessToken, 'yggdrasil');
  }

  /**
   * 刷新 Token
   */
  private async refresh(): Promise<AuthInfo> {
    this.updateStatus('Refreshing login...');

    const refreshBody: YggdrasilTokenRequest = {
      accessToken: this.accessToken,
      clientToken: this.clientToken,
      requestUser: true
    };
    const response = await this.httpPostJSON<YggdrasilRefreshResponse>(
      `${this.serverConfig.apiRoot}/authserver/refresh`,
      refreshBody
    );

    if (response.error) {
      throw new AuthenticationException(`Refresh failed: ${response.errorMessage ?? response.error}`);
    }

    this.accessToken = response.accessToken;
    if (response.selectedProfile) {
      this._character = response.selectedProfile.name;
      this._uuid = response.selectedProfile.id;
    }

    return new AuthInfo(this._character, this._uuid, this.accessToken, 'yggdrasil');
  }

  /**
   * 验证 Token 有效性
   */
  async validate(): Promise<boolean> {
    if (!this.accessToken) {
      return false;
    }

    try {
      const validateBody: YggdrasilTokenRequest = {
        accessToken: this.accessToken,
        clientToken: this.clientToken
      };
      const response = await this.httpPostJSON<Record<string, Object>>(
        `${this.serverConfig.apiRoot}/authserver/validate`,
        validateBody
      );
      return true;
    } catch {
      return false;
    }
  }

  /**
   * 登出 (使 Token 失效)
   */
  async logOut(): Promise<void> {
    try {
      const invalidateBody: YggdrasilTokenRequest = {
        accessToken: this.accessToken,
        clientToken: this.clientToken
      };
      await this.httpPostJSON<Record<string, Object>>(
        `${this.serverConfig.apiRoot}/authserver/invalidate`,
        invalidateBody
      );
    } catch {
      // 忽略登出错误
    } finally {
      this.accessToken = '';
      this.clientToken = '';
    }
  }

  /**
   * 获取角色信息
   */
  private async getProfile(uuid: string): Promise<string> {
    try {
      const response = await this.httpGet(
        `${this.serverConfig.apiRoot}/sessionserver/session/minecraft/profile/${uuid}`
      );
      const data = JSON.parse(response) as Record<string, string>;
      return data['name'] ?? 'Unknown';
    } catch {
      return 'Unknown';
    }
  }

  async playOffline(): Promise<AuthInfo> {
    return new AuthInfo(this._character || this._username, this._uuid, 'offline-token', 'yggdrasil');
  }

  toStorage(): YggdrasilStorage {
    return {
      type: AccountType.YGGDRASIL,
      serverName: this.serverConfig.name,
      apiRoot: this.serverConfig.apiRoot,
      username: this._username,
      uuid: this._uuid,
      character: this._character,
      accessToken: this.accessToken,
      clientToken: this.clientToken
    };
  }

  clearCache(): void {
    this.accessToken = '';
    this.clientToken = '';
  }

  static fromStorage(data: Record<string, Object>): YggdrasilAccount {
    const account = new YggdrasilAccount({
      name: (data['serverName'] as string) ?? '',
      apiRoot: (data['apiRoot'] as string) ?? '',
      skinDomain: data['skinDomain'] as string | undefined,
      registerUrl: data['registerUrl'] as string | undefined
    });
    account._username = (data['username'] as string) ?? '';
    account._uuid = (data['uuid'] as string) ?? '';
    account._character = (data['character'] as string) ?? '';
    account.accessToken = (data['accessToken'] as string) ?? '';
    account.clientToken = (data['clientToken'] as string) ?? '';
    return account;
  }

  // ========== HTTP 工具 ==========

  private async httpPostJSON<T>(url: string, body: Object): Promise<T> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json', 'Accept': 'application/json' },
        extraData: JSON.stringify(body),
        connectTimeout: 10000,
        readTimeout: 20000
      });

      if (response.result) {
        return JSON.parse(response.result as string) as T;
      }
      return JSON.parse('{}') as T;
    } catch (err) {
      const error = err as BusinessError;
      throw new ServerDisconnectException(`Yggdrasil HTTP error: ${error.message}`);
    } finally {
      httpRequest.destroy();
    }
  }

  private async httpGet(url: string): Promise<string> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 10000,
        readTimeout: 15000
      });
      return response.result as string ?? '';
    } catch (err) {
      const error = err as BusinessError;
      throw new ServerDisconnectException(`HTTP GET error: ${error.message}`);
    } finally {
      httpRequest.destroy();
    }
  }

  private updateStatus(status: string): void {
    hilog.info(0x0000, TAG, status);
    if (this.statusCallback) {
      this.statusCallback(status);
    }
  }
}

/**
 * 预置的 Yggdrasil 服务器列表
 * 移植自: FCLCore/auth/AuthlibInjectorServers.java
 */
export class YggdrasilServers {
  static readonly PRESETS: YggdrasilServer[] = [
    {
      name: 'LittleSkin',
      apiRoot: 'https://littleskin.cn/api/yggdrasil',
      skinDomain: 'littleskin.cn',
      registerUrl: 'https://littleskin.cn/user/register'
    },
    {
      name: 'Blessing Skin',
      apiRoot: 'https://mcskin.com.cn/api/yggdrasil',
      skinDomain: 'mcskin.com.cn',
      registerUrl: 'https://mcskin.com.cn/user/register'
    }
  ];

  /** 根据名称查找服务器 */
  static findByName(name: string): YggdrasilServer | null {
    return YggdrasilServers.PRESETS.find(s => s.name === name) ?? null;
  }

  /** 添加自定义服务器 */
  static addCustom(server: YggdrasilServer): void {
    YggdrasilServers.PRESETS.push(server);
  }
}

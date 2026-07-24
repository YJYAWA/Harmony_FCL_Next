/**
 * 账号工厂 - 序列化/反序列化账号
 * 移植自: FCLCore/auth/AccountFactory + various AccountFactory classes
 */
import { Account, AccountType } from './AuthTypes';
import { OfflineAccount } from './OfflineAccount';
import { MicrosoftAccount } from './MicrosoftAccount';
import { YggdrasilAccount } from './YggdrasilAccount';
import { FileUtils } from '../util/FileUtils';
import { AppContext } from '../../common/AppContext';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'FCL-AccountFactory';
const ACCOUNTS_FILE = 'fcl_accounts.json';

/**
 * 账号工厂
 */
export class AccountFactory {
  /** 从存储数据创建账号 */
  static fromStorage(data: Record<string, Object>): Account | null {
    const type = data['type'] as string;

    try {
      switch (type) {
        case AccountType.OFFLINE:
          return OfflineAccount.fromStorage(data);
        case AccountType.MICROSOFT:
          return MicrosoftAccount.fromStorage(data);
        case AccountType.YGGDRASIL:
          return YggdrasilAccount.fromStorage(data);
        default:
          hilog.warn(0x0000, TAG, `Unknown account type: ${type}`);
          return null;
      }
    } catch (err) {
      hilog.error(0x0000, TAG, `Failed to create account: ${err}`);
      return null;
    }
  }

  /** 加载所有账号 */
  static loadAll(): Account[] {
    const path = `${AppContext.filesDir}/${ACCOUNTS_FILE}`;
    const data = FileUtils.readJSON<Array<Record<string, Object>>>(path);

    if (!data || !Array.isArray(data)) {
      return [];
    }

    const accounts: Account[] = [];
    for (const item of data) {
      const account = AccountFactory.fromStorage(item);
      if (account) {
        accounts.push(account);
      }
    }

    return accounts;
  }

  /** 保存所有账号 */
  static saveAll(accounts: Account[]): boolean {
    const path = `${AppContext.filesDir}/${ACCOUNTS_FILE}`;
    const data = accounts.map(a => a.toStorage());
    return FileUtils.writeJSON(path, data);
  }

  /** 添加账号 */
  static add(account: Account): boolean {
    const accounts = AccountFactory.loadAll();
    // 检查重复
    const existing = accounts.findIndex(a => a.identifier === account.identifier);
    if (existing >= 0) {
      accounts[existing] = account;
    } else {
      accounts.push(account);
    }
    return AccountFactory.saveAll(accounts);
  }

  /** 删除账号 */
  static remove(identifier: string): boolean {
    const accounts = AccountFactory.loadAll();
    const filtered = accounts.filter(a => a.identifier !== identifier);
    if (filtered.length === accounts.length) {
      return false; // 没有找到
    }
    return AccountFactory.saveAll(filtered);
  }

  /** 查找账号 */
  static find(identifier: string): Account | null {
    const accounts = AccountFactory.loadAll();
    return accounts.find(a => a.identifier === identifier) ?? null;
  }

  /** 获取账号数量 */
  static count(): number {
    return AccountFactory.loadAll().length;
  }
}

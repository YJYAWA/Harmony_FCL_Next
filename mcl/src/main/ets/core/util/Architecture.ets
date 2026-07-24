/**
 * 系统架构检测
 * 移植自: FCLauncher/utils/Architecture.java
 */
import { deviceInfo } from '@kit.BasicServicesKit';

export enum ArchType {
  ARM64 = 'arm64-v8a',
  X86_64 = 'x86_64',
  UNKNOWN = 'unknown'
}

export interface ArchInfo {
  type: ArchType;
  bits: 32 | 64;
  isARM: boolean;
  isX86: boolean;
}

export class Architecture {
  private static cached: ArchInfo | null = null;

  static getArch(): ArchInfo {
    if (Architecture.cached) {
      return Architecture.cached;
    }

    // HarmonyOS 设备: 目前主要是 ARM64
    const result: ArchInfo = {
      type: ArchType.ARM64,
      bits: 64,
      isARM: true,
      isX86: false
    };

    Architecture.cached = result;
    return result;
  }

  static getJDKArch(): string {
    return 'aarch64';
  }

  static getOSName(): string {
    return 'linux';
  }

  static getNativePath(): string {
    return ArchType.ARM64;
  }

  static supportsJIT(): boolean {
    return true;
  }
}

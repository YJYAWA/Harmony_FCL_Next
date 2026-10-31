/**
 * fcl_fork_jar.h — FCL 安装器子进程封装
 *
 * 在 AMCL (GPL-3.0) 的 JVM 嵌入 API（jvmInit/fork 保留协议）之上，
 * 提供 `java -jar` 等价操作：从 jar 的 META-INF/MANIFEST.MF 读 Main-Class
 * （纯 C ZIP 解析 + zlib raw inflate，不依赖 JVM），再 fork 子进程运行。
 */
#ifndef FCL_FORK_JAR_H
#define FCL_FORK_JAR_H

#include <string>
#include <vector>

/** 从 jar manifest 读取 Main-Class；失败返回空串 */
std::string fclReadMainClassFromJar(const std::string& jarPath);

/**
 * fork 子进程运行 `java -jar <jarPath> [programArgs...]`（AMCL 语义：复用
 * jvmInit + jvmCallMain，含 pre-JVM 信号链桥，JDK 21/25 不会 init 期崩）。
 * 返回父进程视角的子进程退出码（负数=内部错误）。
 */
int fclForkRunJar(const std::string& filesDir, const std::string& jdkDir,
                  const std::string& jarPath,
                  const std::vector<std::string>& jvmArgs,
                  const std::vector<std::string>& programArgs,
                  const std::string& workDir,
                  const std::string& logFile,
                  int xmxMb);

#endif // FCL_FORK_JAR_H

# 数据库自动迁移方案

## 问题描述

编译后的 Windows 二进制文件启动时报错：
```
** (Exqlite.Error) no such table: channel_configs
```

根本原因：数据库表未创建，迁移未自动执行。

## 问题分析

### 原有实现的局限性

```elixir
# 旧代码
if System.get_env("RELEASE_NAME") do
  prepare_database()
end
```

**问题**：
1. 依赖单一环境变量 `RELEASE_NAME`
2. Burrito 打包的二进制在某些场景下可能未正确设置该变量
3. 缺少数据库目录自动创建逻辑
4. 缺少迁移失败的错误处理

### 构建流程分析

从 `.github/workflows/release.yml` 可知：
- 使用 `MIX_ENV=prod` 编译
- 通过 Burrito 打包为单文件二进制
- `mix.exs` 中配置了 `RELEASE_NAME => "cortex"`

但环境变量在不同运行环境下可能不一致。

## 解决方案

### 核心改进

1. **多条件检测机制**
   ```elixir
   defp should_prepare_database? do
     System.get_env("RELEASE_NAME") != nil or
       Application.get_env(:cortex, :env) == :prod or
       Mix.env() == :prod or
       not Code.ensure_loaded?(Mix)
   end
   ```

   检测逻辑：
   - `RELEASE_NAME` 环境变量（标准 release）
   - `:cortex` 应用的 `:env` 配置
   - `Mix.env()` 编译环境
   - `Code.ensure_loaded?(Mix)` 检测是否为打包环境（打包后 Mix 不可用）

2. **数据库目录自动创建**
   ```elixir
   defp ensure_database_directory(repo) do
     case Keyword.get(repo.config(), :database) do
       nil -> :ok
       db_path ->
         db_dir = Path.dirname(db_path)
         unless File.exists?(db_dir) do
           Logger.info("[Application] Creating database directory: #{db_dir}")
           File.mkdir_p!(db_dir)
         end
     end
   end
   ```

3. **增强的错误处理**
   ```elixir
   try do
     Ecto.Migrator.run(repo, migrations_path, :up, all: true)
     Logger.info("[Application] Migrations completed successfully")
   rescue
     e ->
       Logger.error("[Application] Migration failed: #{Exception.message(e)}")
       reraise e, __STACKTRACE__
   end
   ```

### 完整流程

```
Application.start/2
  ↓
should_prepare_database?() → true (多条件检测)
  ↓
prepare_database()
  ↓
for each repo:
  1. ensure_database_directory() → 创建数据库目录
  2. repo.start_link() → 启动 Repo
  3. run_migrations() → 执行迁移
  4. repo.stop() → 停止临时 Repo
  ↓
启动正常的 supervision tree
```

## 最佳实践

### 1. 环境检测优先级

```
1. Code.ensure_loaded?(Mix) → 最可靠（打包后 Mix 不存在）
2. RELEASE_NAME 环境变量 → 标准 Elixir release
3. MIX_ENV / :env 配置 → 编译时环境
```

### 2. 数据库路径处理

- **开发环境**：`cortex_dev.db`（项目根目录）
- **生产环境**：`DATABASE_PATH` 环境变量或默认 `cortex.db`
- **自动创建**：确保父目录存在

### 3. 迁移时机

- 在 Repo 正式启动前运行
- 使用独立的 `pool_size: 2` 连接池
- 迁移完成后停止临时 Repo

### 4. 日志记录

```elixir
Logger.info("[Application] Running migrations for #{inspect(repo)}")
Logger.info("[Application] Migrations completed successfully")
Logger.error("[Application] Migration failed: #{Exception.message(e)}")
```

## 测试验证

### 本地测试

```bash
# 1. 编译生产版本
MIX_ENV=prod mix release cortex --overwrite

# 2. 运行二进制
./burrito_out/cortex_windows.exe  # Windows
./burrito_out/cortex_linux         # Linux

# 3. 检查日志
# 应看到：
# [Application] Running migrations for Elixir.Cortex.Repo
# [Application] Migrations completed successfully
```

### CI/CD 验证

GitHub Actions 构建流程会自动测试所有平台：
- Linux x86_64
- Windows x86_64
- macOS aarch64

## 相关文件

- `lib/cortex/application.ex` - 主要修改
- `config/runtime.exs` - 数据库路径配置
- `mix.exs` - Release 配置
- `.github/workflows/release.yml` - CI/CD 流程

## 参考

- [Ecto.Migrator](https://hexdocs.pm/ecto_sql/Ecto.Migrator.html)
- [Mix.Release](https://hexdocs.pm/mix/Mix.Tasks.Release.html)
- [Burrito](https://github.com/burrito-elixir/burrito)

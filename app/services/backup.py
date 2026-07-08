"""Create MariaDB dump + .env zip and send to the backup log channel."""

from __future__ import annotations

import asyncio
import os
import shutil
import tempfile
import zipfile
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from urllib.parse import unquote, urlparse

from app.db.crud.log_channels import LogChannelManager
from app.logger import LogTag, LogType, get_logger
from app.telegram.shared.utils.logging import send_log_message
from config import SQLALCHEMY_DATABASE_URL

logger = get_logger(__name__)

BACKUP_JOB_ID = "bot_backup"


@dataclass(frozen=True)
class MysqlConnection:
    host: str
    port: int
    user: str
    password: str
    database: str


@dataclass
class BackupResult:
    ok: bool
    message: str
    sent: bool = False


def parse_mysql_url(database_url: str = SQLALCHEMY_DATABASE_URL) -> MysqlConnection:
    parsed = urlparse(database_url)
    scheme = (parsed.scheme or "").split("+", 1)[0].lower()
    if scheme not in {"mysql", "mariadb"}:
        raise ValueError("بکاپ فقط برای MariaDB/MySQL پشتیبانی می‌شود.")
    if not parsed.hostname or not parsed.path or parsed.path == "/":
        raise ValueError("آدرس دیتابیس نامعتبر است.")
    return MysqlConnection(
        host=parsed.hostname,
        port=parsed.port or 3306,
        user=unquote(parsed.username or ""),
        password=unquote(parsed.password or ""),
        database=unquote(parsed.path.lstrip("/")),
    )


def _resolve_dump_binary() -> str:
    for name in ("mariadb-dump", "mysqldump"):
        path = shutil.which(name)
        if path:
            return path
    raise FileNotFoundError("mariadb-dump/mysqldump روی سیستم پیدا نشد.")


def _write_sql_file(sql_path: Path, data: bytes) -> None:
    sql_path.write_bytes(data)
    if sql_path.stat().st_size == 0:
        raise RuntimeError("فایل dump دیتابیس خالی است.")


async def _run_mariadb_dump(conn: MysqlConnection, sql_path: Path) -> None:
    dump_bin = _resolve_dump_binary()
    cmd = [
        dump_bin,
        f"--host={conn.host}",
        f"--port={conn.port}",
        f"--user={conn.user}",
        "--single-transaction",
        "--routines",
        "--triggers",
        "--hex-blob",
        "--databases",
        conn.database,
    ]
    env = os.environ.copy()
    if conn.password:
        env["MYSQL_PWD"] = conn.password

    process = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
        env=env,
    )
    stdout, stderr = await process.communicate()
    if process.returncode != 0:
        err = (stderr or b"").decode("utf-8", errors="replace").strip() or "unknown dump error"
        raise RuntimeError(f"خطا در dump دیتابیس: {err}")
    await asyncio.to_thread(_write_sql_file, sql_path, stdout)


def _project_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _env_file_path() -> Path | None:
    for path in (Path(".env"), _project_root() / ".env", Path("/app/.env")):
        if path.is_file():
            return path
    return None


def _build_zip_sync(work_dir: Path, sql_path: Path, zip_path: Path) -> Path:
    work_dir.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        zf.write(sql_path, arcname="database.sql")
        env_path = _env_file_path()
        if env_path is not None:
            zf.write(env_path, arcname=".env")
        else:
            logger.warning("%s .env not found — backup zip contains database only", LogTag.JOB)
    return zip_path


async def create_backup_zip(work_dir: Path) -> Path:
    conn = parse_mysql_url()
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    sql_path = work_dir / "database.sql"
    zip_path = work_dir / f"pasarguardbot-backup-{stamp}.zip"

    await _run_mariadb_dump(conn, sql_path)
    return await asyncio.to_thread(_build_zip_sync, work_dir, sql_path, zip_path)


async def run_backup_and_send(*, trigger: str = "auto") -> BackupResult:
    destination = await LogChannelManager().get_log_channel_destination(LogType.BACKUP.value)
    if not destination:
        return BackupResult(
            ok=False,
            message=("کانال لاگ «🗄 بکاپ ربات» تنظیم نشده است.\nاز مسیر «مدیریت لاگ‌ها» اول کانال بکاپ را ست کنید."),
            sent=False,
        )

    temp_dir = Path(await asyncio.to_thread(tempfile.mkdtemp, "pasarguardbot-backup-"))
    try:
        zip_path = await create_backup_zip(temp_dir)
        size_mb = (await asyncio.to_thread(zip_path.stat)).st_size / (1024 * 1024)
        caption = f"🗄 **بکاپ ربات**\n🔹 نوع: `{trigger}`\n📦 فایل: `{zip_path.name}`\n💾 حجم: `{size_mb:.2f}` MB"
        sent = await send_log_message(
            LogType.BACKUP,
            file=str(zip_path),
            caption=caption,
            force_document=True,
            parse_mode="md",
        )
        if sent is None:
            return BackupResult(ok=False, message="❌ ارسال بکاپ به کانال ناموفق بود.", sent=False)
        return BackupResult(
            ok=True,
            message=f"✅ بکاپ با موفقیت ارسال شد ({size_mb:.2f} MB).",
            sent=True,
        )
    except Exception as exc:
        logger.error("%s Backup failed: %s", LogTag.JOB, exc, exc_info=True)
        return BackupResult(ok=False, message=f"❌ خطا در بکاپ: {exc}", sent=False)
    finally:
        await asyncio.to_thread(shutil.rmtree, temp_dir, True)

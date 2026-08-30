#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import stat
import subprocess
from collections.abc import Callable
from pathlib import Path

MINIMUM_VERSION = (0, 9, 0)


class ContractError(RuntimeError):
    pass


def _trusted_directory(parent_fd: int, name: str, display: str, owner: int) -> int:
    try:
        descriptor = os.open(
            name,
            os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
            dir_fd=parent_fd,
        )
    except OSError as error:
        raise ContractError(f"{display} is not a trusted directory") from error

    metadata = os.fstat(descriptor)
    if metadata.st_uid != owner or metadata.st_gid != owner:
        os.close(descriptor)
        raise ContractError(f"{display} must be owned by root:root")
    if stat.S_IMODE(metadata.st_mode) & 0o022:
        os.close(descriptor)
        raise ContractError(f"{display} must not be group- or world-writable")
    return descriptor


def _open_bubblewrap(bin_fd: int, owner: int) -> tuple[int, os.stat_result]:
    try:
        descriptor = os.open(
            "bwrap", os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=bin_fd
        )
    except OSError as error:
        raise ContractError("/usr/bin/bwrap is not an exact regular file") from error

    metadata = os.fstat(descriptor)
    if not stat.S_ISREG(metadata.st_mode):
        os.close(descriptor)
        raise ContractError("/usr/bin/bwrap is not an exact regular file")
    if metadata.st_uid != owner or metadata.st_gid != owner:
        os.close(descriptor)
        raise ContractError("/usr/bin/bwrap must be owned by root:root")
    mode = stat.S_IMODE(metadata.st_mode)
    if mode & 0o022:
        os.close(descriptor)
        raise ContractError("/usr/bin/bwrap must not be group- or world-writable")
    if not mode & 0o111:
        os.close(descriptor)
        raise ContractError("/usr/bin/bwrap must be executable")
    return descriptor, metadata


def verify_bubblewrap(
    root: Path = Path("/"),
    *,
    owner: int = 0,
    before_execute: Callable[[], None] | None = None,
) -> None:
    def identity(metadata: os.stat_result) -> tuple[int, ...]:
        return (
            metadata.st_dev,
            metadata.st_ino,
            metadata.st_uid,
            metadata.st_gid,
            stat.S_IMODE(metadata.st_mode),
            metadata.st_size,
            metadata.st_mtime_ns,
            metadata.st_ctime_ns,
        )

    try:
        root_fd = os.open(
            root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC
        )
    except OSError as error:
        raise ContractError("/ is not a trusted directory") from error

    descriptors = [root_fd]
    try:
        root_metadata = os.fstat(root_fd)
        if root_metadata.st_uid != owner or root_metadata.st_gid != owner:
            raise ContractError("/ must be owned by root:root")
        if stat.S_IMODE(root_metadata.st_mode) & 0o022:
            raise ContractError("/ must not be group- or world-writable")

        usr_fd = _trusted_directory(root_fd, "usr", "/usr", owner)
        descriptors.append(usr_fd)
        usr_before = os.fstat(usr_fd)
        bin_fd = _trusted_directory(usr_fd, "bin", "/usr/bin", owner)
        descriptors.append(bin_fd)
        bin_before = os.fstat(bin_fd)
        bubblewrap_fd, before = _open_bubblewrap(bin_fd, owner)
        descriptors.append(bubblewrap_fd)

        if before_execute is not None:
            before_execute()

        result = subprocess.run(
            [f"/proc/self/fd/{bubblewrap_fd}", "--version"],
            pass_fds=(bubblewrap_fd,),
            check=False,
            capture_output=True,
            text=True,
            env={"LC_ALL": "C"},
        )
        if result.returncode != 0:
            raise ContractError("/usr/bin/bwrap --version failed")

        match = re.fullmatch(r"bubblewrap ([0-9]+)\.([0-9]+)\.([0-9]+)\n?", result.stdout)
        if match is None:
            raise ContractError("/usr/bin/bwrap emitted an unsupported version string")
        if tuple(map(int, match.groups())) < MINIMUM_VERSION:
            raise ContractError("/usr/bin/bwrap is older than 0.9.0")

        usr_after_fd = _trusted_directory(root_fd, "usr", "/usr", owner)
        descriptors.append(usr_after_fd)
        bin_after_fd = _trusted_directory(usr_after_fd, "bin", "/usr/bin", owner)
        descriptors.append(bin_after_fd)
        after_fd, after = _open_bubblewrap(bin_after_fd, owner)
        descriptors.append(after_fd)
        if (
            identity(usr_before) != identity(os.fstat(usr_fd))
            or identity(usr_before) != identity(os.fstat(usr_after_fd))
            or identity(bin_before) != identity(os.fstat(bin_fd))
            or identity(bin_before) != identity(os.fstat(bin_after_fd))
            or identity(before) != identity(os.fstat(bubblewrap_fd))
            or identity(before) != identity(after)
        ):
            raise ContractError("/usr/bin/bwrap changed during verification")
    finally:
        for descriptor in reversed(descriptors):
            os.close(descriptor)


if __name__ == "__main__":
    try:
        verify_bubblewrap()
    except ContractError as error:
        raise SystemExit(f"bubblewrap image contract: {error}") from None

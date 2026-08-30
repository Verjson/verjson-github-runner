#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import os
import re
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTRACT_PATH = ROOT / "scripts" / "bubblewrap-image-contract.py"
SPEC = importlib.util.spec_from_file_location("bubblewrap_image_contract", CONTRACT_PATH)
assert SPEC is not None and SPEC.loader is not None
CONTRACT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CONTRACT)
FINAL_CONTRACT = 'RUN ["/usr/local/bin/bubblewrap-image-contract"]'
FINAL_CONTRACT_ARGUMENTS = '["/usr/local/bin/bubblewrap-image-contract"]'
HEREDOC = re.compile(r"<<(-?)(?:'([^']+)'|\"([^\"]+)\"|([A-Za-z0-9_.-]+))")


def dockerfile_instructions(dockerfile: str) -> list[tuple[str, str]]:
    instructions: list[tuple[str, str]] = []
    continuation = ""
    heredocs: list[tuple[str, bool]] = []
    for physical_line in dockerfile.splitlines():
        if heredocs:
            delimiter, strip_tabs = heredocs[0]
            candidate = physical_line.lstrip("\t") if strip_tabs else physical_line
            if candidate == delimiter:
                heredocs.pop(0)
            continue

        stripped = physical_line.strip()
        if not continuation and (not stripped or stripped.startswith("#")):
            continue
        if continuation and stripped.startswith("#"):
            continue

        continued = stripped.endswith("\\")
        fragment = stripped[:-1].rstrip() if continued else stripped
        continuation = f"{continuation} {fragment}".strip()
        if continued:
            continue

        parsed = re.fullmatch(r"([A-Za-z]+)(?:[ \t]+(.*))?", continuation)
        if parsed is None:
            raise AssertionError(f"invalid Dockerfile instruction: {continuation}")
        instruction, arguments = parsed.groups()
        arguments = (arguments or "").strip()
        instructions.append((instruction.upper(), arguments))
        for match in HEREDOC.finditer(arguments):
            delimiter = next(group for group in match.groups()[1:] if group is not None)
            heredocs.append((delimiter, match.group(1) == "-"))
        continuation = ""

    if continuation:
        raise AssertionError("unterminated Dockerfile continuation")
    if heredocs:
        raise AssertionError("unterminated Dockerfile heredoc")
    return instructions


def assert_final_contract(
    test: unittest.TestCase,
    dockerfile: str,
    allowed_after: tuple[tuple[str, str], ...] = (),
) -> None:
    contract_seen = False
    post_contract: list[tuple[str, str]] = []
    for instruction, arguments in dockerfile_instructions(dockerfile):
        is_contract = instruction == "RUN" and arguments == FINAL_CONTRACT_ARGUMENTS
        if is_contract:
            test.assertFalse(contract_seen, "duplicate final Bubblewrap contract")
            contract_seen = True
            continue
        if contract_seen:
            post_contract.append((instruction, arguments))
    test.assertTrue(contract_seen, "final Bubblewrap contract is missing")
    test.assertEqual(tuple(post_contract), allowed_after)


class BubblewrapBehaviorTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.bin = self.root / "usr" / "bin"
        self.bin.mkdir(parents=True)
        self.root.chmod(0o755)
        (self.root / "usr").chmod(0o755)
        self.bin.chmod(0o755)
        self.owner = os.getuid()
        self.write_bwrap("0.9.0")

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def write_bwrap(self, version: str, path: Path | None = None) -> Path:
        target = path or self.bin / "bwrap"
        target.write_text(f"#!/bin/sh\nprintf 'bubblewrap {version}\\n'\n", encoding="utf-8")
        target.chmod(0o755)
        return target

    def verify(self, **kwargs: object) -> None:
        CONTRACT.verify_bubblewrap(self.root, owner=self.owner, **kwargs)

    def test_accepts_exact_minimum_version(self) -> None:
        self.verify()

    def test_rejects_missing_binary(self) -> None:
        (self.bin / "bwrap").unlink()
        with self.assertRaises(CONTRACT.ContractError):
            self.verify()

    def test_rejects_symlinked_binary(self) -> None:
        (self.bin / "bwrap").unlink()
        target = self.write_bwrap("0.9.0", self.bin / "replacement")
        (self.bin / "bwrap").symlink_to(target.name)
        with self.assertRaises(CONTRACT.ContractError):
            self.verify()

    def test_rejects_group_writable_binary(self) -> None:
        (self.bin / "bwrap").chmod(0o775)
        with self.assertRaises(CONTRACT.ContractError):
            self.verify()

    def test_rejects_wrong_owner(self) -> None:
        with self.assertRaises(CONTRACT.ContractError):
            CONTRACT.verify_bubblewrap(self.root, owner=self.owner + 1)

    def test_rejects_untrusted_ancestry(self) -> None:
        (self.root / "usr").chmod(0o775)
        with self.assertRaises(CONTRACT.ContractError):
            self.verify()

    def test_rejects_symlinked_ancestry(self) -> None:
        (self.root / "usr").rename(self.root / "real-usr")
        (self.root / "usr").symlink_to("real-usr", target_is_directory=True)
        with self.assertRaises(CONTRACT.ContractError):
            self.verify()

    def test_rejects_version_below_floor(self) -> None:
        self.write_bwrap("0.8.0")
        with self.assertRaises(CONTRACT.ContractError):
            self.verify()

    def test_rejects_path_replacement_during_descriptor_bound_execution(self) -> None:
        replacement = self.write_bwrap("99.0.0", self.bin / "replacement")

        def replace() -> None:
            replacement.replace(self.bin / "bwrap")

        with self.assertRaisesRegex(CONTRACT.ContractError, "changed during verification"):
            self.verify(before_execute=replace)

    def test_rejects_ancestry_replacement_during_descriptor_bound_execution(self) -> None:
        def replace() -> None:
            (self.root / "usr").rename(self.root / "original-usr")
            replacement_bin = self.root / "usr" / "bin"
            replacement_bin.mkdir(parents=True)
            self.root.chmod(0o755)
            (self.root / "usr").chmod(0o755)
            replacement_bin.chmod(0o755)
            self.write_bwrap("99.0.0", replacement_bin / "bwrap")

        with self.assertRaisesRegex(CONTRACT.ContractError, "changed during verification"):
            self.verify(before_execute=replace)


class PublishedImageContractTest(unittest.TestCase):
    def test_every_published_variant_and_architecture_runs_final_contract(self) -> None:
        config = json.loads((ROOT / "container-candidate.json").read_text(encoding="utf-8"))
        images = config["images"]
        self.assertEqual(
            {image["variant"] for image in images},
            {"base", "rust", "node", "python", "go", "pwsh"},
        )
        expected_platforms = {("linux", "amd64"), ("linux", "arm64")}
        for image in images:
            with self.subTest(variant=image["variant"]):
                self.assertEqual(
                    {(platform["os"], platform["architecture"]) for platform in image["platforms"]},
                    expected_platforms,
                )
                dockerfile = (ROOT / image["file"]).read_text(encoding="utf-8")
                allowed_after = (
                    (("ENTRYPOINT", '["/entrypoint.sh"]'),)
                    if image["variant"] == "base"
                    else ()
                )
                assert_final_contract(self, dockerfile, allowed_after)

    def test_removing_final_contract_fails(self) -> None:
        with self.assertRaises(AssertionError):
            assert_final_contract(self, "FROM base\nUSER runner\n")

    def test_replacing_bwrap_after_final_contract_fails(self) -> None:
        mutated = (
            "FROM base\n"
            f"{FINAL_CONTRACT}\n"
            "COPY replacement /usr/bin/bwrap\n"
        )
        with self.assertRaises(AssertionError):
            assert_final_contract(self, mutated)

    def test_later_from_scratch_fails(self) -> None:
        mutated = f"FROM base\n{FINAL_CONTRACT}\nFROM scratch\n"
        with self.assertRaises(AssertionError):
            assert_final_contract(self, mutated)

    def test_lowercase_mutation_after_final_contract_fails(self) -> None:
        mutated = f"FROM base\n{FINAL_CONTRACT}\nrun touch /usr/bin/bwrap\n"
        with self.assertRaises(AssertionError):
            assert_final_contract(self, mutated)

    def test_leading_whitespace_mutation_after_final_contract_fails(self) -> None:
        mutated = f"FROM base\n{FINAL_CONTRACT}\n  COPY replacement /usr/bin/bwrap\n"
        with self.assertRaises(AssertionError):
            assert_final_contract(self, mutated)

    def test_continued_contract_with_extra_command_fails(self) -> None:
        mutated = (
            "FROM base\n"
            f"{FINAL_CONTRACT} \\\n"
            "  && touch /usr/bin/bwrap\n"
        )
        with self.assertRaises(AssertionError):
            assert_final_contract(self, mutated)

    def test_comment_inside_mutating_continuation_does_not_hide_it(self) -> None:
        mutated = (
            "FROM base\n"
            f"{FINAL_CONTRACT} \\\n"
            "  # ignored continuation comment\n"
            "  && touch /usr/bin/bwrap\n"
        )
        with self.assertRaises(AssertionError):
            assert_final_contract(self, mutated)

    def test_comments_and_entrypoint_after_final_contract_are_accepted(self) -> None:
        dockerfile = (
            "FROM base\n"
            f"  {FINAL_CONTRACT}\n"
            "  # a comment is not an instruction\n"
            "entrypoint [\"/entrypoint.sh\"]\n"
        )
        assert_final_contract(
            self, dockerfile, (("ENTRYPOINT", '["/entrypoint.sh"]'),)
        )

    def test_hostile_entrypoint_after_final_contract_fails(self) -> None:
        mutated = (
            "FROM base\n"
            f"{FINAL_CONTRACT}\n"
            "ENTRYPOINT [\"/bin/true\"]\n"
        )
        with self.assertRaises(AssertionError):
            assert_final_contract(
                self, mutated, (("ENTRYPOINT", '["/entrypoint.sh"]'),)
            )

    def test_shell_form_contract_under_hostile_shell_fails(self) -> None:
        mutated = (
            "FROM base\n"
            "SHELL [\"/bin/true\"]\n"
            "RUN /usr/local/bin/bubblewrap-image-contract\n"
        )
        with self.assertRaises(AssertionError):
            assert_final_contract(self, mutated)

    def test_false_contract_inside_run_heredoc_fails(self) -> None:
        mutated = (
            "FROM base\n"
            "RUN <<'SCRIPT'\n"
            f"{FINAL_CONTRACT}\n"
            "SCRIPT\n"
        )
        with self.assertRaises(AssertionError):
            assert_final_contract(self, mutated)


if __name__ == "__main__":
    unittest.main()

"""仓库内示例启动配置必须始终能被对应 CLI 的 load_config 读取。"""

import unittest
from pathlib import Path

from acn_deepswe.auto_run import load_config as load_auto_run_config
from acn_deepswe.presmoke_cli import load_config as load_presmoke_config

MANIFESTS = Path(__file__).resolve().parents[1] / "manifests"


class ExampleManifestTests(unittest.TestCase):
    def test_presmoke_examples_load(self) -> None:
        for name in ("presmoke-run.example.json", "claim-harness-paired.example.json"):
            with self.subTest(name=name):
                config = load_presmoke_config(MANIFESTS / name)
                self.assertTrue(config.acn_checkout.is_absolute())
                self.assertEqual(config.model_egress_mode, "pier")

    def test_automated_run_examples_load(self) -> None:
        for name in (
            "automated-run.example.json",
            "automated-run-solver-aligned-full.example.json",
        ):
            with self.subTest(name=name):
                config = load_auto_run_config(MANIFESTS / name)
                self.assertTrue(config.acn_checkout.is_absolute())
                self.assertEqual(config.run_class, "formal")
                self.assertEqual(config.full_size, 113)

    def test_examples_carry_no_real_model_alias_or_credential(self) -> None:
        for path in MANIFESTS.glob("*.example.json"):
            text = path.read_text(encoding="utf-8")
            with self.subTest(name=path.name):
                self.assertIn('"model": "frozen-model-alias"', text)
                self.assertNotIn("ACN_EVAL_UPSTREAM_KEY", text)


if __name__ == "__main__":
    unittest.main()

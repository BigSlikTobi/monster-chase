import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from analysis import run_codex, validate_result
from setup import configure_models
from test_pipeline import result


class ModelConfigTests(unittest.TestCase):
    def test_migrates_legacy_astra_to_luna_with_sol_fallback(self):
        config = configure_models({"model": "gpt-6-astra", "reasoningEffort": "ultra"})
        self.assertEqual(config["model"], "gpt-6-luna")
        self.assertEqual(config["reasoningEffort"], "max")
        self.assertEqual(config["fallbackModel"], "gpt-5.6-sol")
        self.assertEqual(config["fallbackReasoningEffort"], "max")
        self.assertEqual(config["modelRoutingVersion"], 2)

    def test_upgrades_managed_route_without_changing_pairing_or_stage_effort(self):
        original = {"modelRoutingVersion": 1, "model": "gpt-5.6-luna", "reasoningEffort": "max",
                    "fallbackModel": "gpt-5.6-sol", "fallbackReasoningEffort": "max",
                    "scanReasoningEffort": "medium", "marketReasoningEffort": "medium",
                    "token": "fixture-pairing", "port": 8743}
        updated = configure_models(dict(original))
        self.assertEqual(updated, dict(original, model="gpt-6-luna", modelRoutingVersion=2))
        self.assertEqual(configure_models(dict(updated)), updated)

    def test_preserves_explicit_routing_after_migration(self):
        original = {"modelRoutingVersion": 1, "model": "custom-primary", "reasoningEffort": "high",
                    "fallbackModel": "custom-fallback", "fallbackReasoningEffort": "xhigh"}
        self.assertEqual(configure_models(dict(original)), original)


class ModelRoutingTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.folder = Path(self.temp.name)
        self.config = {"codex": "/test/codex", "model": "gpt-5.6-luna", "reasoningEffort": "max",
                       "fallbackModel": "gpt-5.6-sol", "fallbackReasoningEffort": "max"}

    def tearDown(self):
        self.temp.cleanup()

    def test_confirmed_identity_does_not_escalate_for_missing_price(self):
        confirmed = validate_result(result(), [])
        with patch("analysis._run_model", return_value=confirmed) as runner:
            output = run_codex(self.folder, [], self.config)
        self.assertIs(output, confirmed)
        self.assertEqual(runner.call_count, 1)
        self.assertEqual(runner.call_args.args[6:8], ("gpt-5.6-luna", "max"))

    def test_uncertain_identity_escalates_to_sol(self):
        uncertain_data = result()
        uncertain_data["analysis"]["player"] = "Unknown Player"
        uncertain = validate_result(uncertain_data, [])
        confirmed = validate_result(result(), [])
        with patch("analysis._run_model", side_effect=[uncertain, confirmed]) as runner:
            output = run_codex(self.folder, [], self.config)
        self.assertIs(output, confirmed)
        self.assertEqual(runner.call_count, 2)
        self.assertEqual(runner.call_args_list[1].args[6:8], ("gpt-5.6-sol", "max"))

    def test_cardsight_keeps_sol_for_uncertainty_without_enabling_search(self):
        uncertain = validate_result(result(), [])
        uncertain['analysis']['identityConfirmed'] = False
        confirmed = validate_result(result(), [])
        config = dict(self.config, cardSightResearchEnabled=True, webSearch='live')
        with patch('analysis._run_model', side_effect=[uncertain, confirmed]) as runner, patch('retrieval.retrieve') as retrieval:
            self.assertIs(run_codex(self.folder, [], config), confirmed)
        retrieval.assert_not_called()
        self.assertEqual(runner.call_count, 2)
        for call in runner.call_args_list: self.assertEqual(call.args[2]['webSearch'], 'disabled')
        self.assertEqual(runner.call_args_list[1].args[6:8], ('gpt-5.6-sol', 'max'))

    def test_invalid_photo_stage_reaches_sol_full_analysis_once(self):
        c = result()['collection']; c['checklistComplete'] = True
        with patch('analysis.run_identification', side_effect=ValueError('bad photo contract')), patch('analysis._run_model', return_value=result()) as runner:
            run_codex(self.folder, [c], dict(self.config, cardSightResearchEnabled=True))
        self.assertEqual(runner.call_count, 1)
        self.assertEqual(runner.call_args.args[6:8], ('gpt-5.6-sol', 'max'))

    def test_medium_identity_confidence_escalates_even_if_flags_are_inconsistent(self):
        medium_data = result()
        medium_data["analysis"]["confidence"] = "medium"
        medium = validate_result(medium_data, [])
        confirmed = validate_result(result(), [])
        with patch("analysis._run_model", side_effect=[medium, confirmed]) as runner:
            output = run_codex(self.folder, [], self.config)
        self.assertIs(output, confirmed)
        self.assertEqual(runner.call_count, 2)

    def test_invalid_luna_result_escalates_to_sol(self):
        confirmed = validate_result(result(), [])
        with patch("analysis._run_model", side_effect=[ValueError("invalid contract"), confirmed]) as runner:
            output = run_codex(self.folder, [], self.config)
        self.assertIs(output, confirmed)
        self.assertEqual(runner.call_count, 2)

    def test_worker_outage_or_timeout_does_not_escalate_to_sol(self):
        for error in (RuntimeError("Worker unavailable"), KeyError("config"), TypeError("config")):
            with self.subTest(error=type(error).__name__):
                with patch("analysis._run_model", side_effect=error) as runner:
                    with self.assertRaises(type(error)): run_codex(self.folder, [], self.config)
                self.assertEqual(runner.call_count, 1)

    def test_new_default_is_luna6_when_no_primary_is_configured(self):
        confirmed = validate_result(result(), [])
        with patch("analysis._run_model", return_value=confirmed) as runner:
            run_codex(self.folder, [], {"codex": "/test/codex"})
        self.assertEqual(runner.call_args.args[6:8], ("gpt-6-luna", "max"))

    def test_sol_failure_keeps_valid_provisional_luna_result(self):
        uncertain_data = result()
        uncertain_data["analysis"]["licenseScope"] = "unknown"
        uncertain = validate_result(uncertain_data, [])
        with patch("analysis._run_model", side_effect=[uncertain, RuntimeError("Sol unavailable")]) as runner:
            output = run_codex(self.folder, [], self.config)
        self.assertIs(output, uncertain)
        self.assertEqual(runner.call_count, 2)

    def test_market_only_refresh_never_escalates_for_identity(self):
        previous = validate_result(result(), [])
        (self.folder / "refresh.json").write_text(__import__("json").dumps(previous))
        with patch("analysis._run_model", return_value=previous) as runner:
            output = run_codex(self.folder, [], self.config)
        self.assertIs(output, previous)
        self.assertEqual(runner.call_count, 1)


if __name__ == "__main__":
    unittest.main()

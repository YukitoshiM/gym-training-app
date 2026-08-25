import json
import tempfile
import unittest
from pathlib import Path

from audit_workout_export import audit_csv, audit_file, audit_json


class WorkoutExportAuditTests(unittest.TestCase):
    def test_strong_csv_requires_weight_unit_confirmation_without_unit_column(self):
        content = (
            "Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE\r\n"
            '2026-08-01,Private Workout,00:45:00,"Private Exercise",1,60,8,,,private note,,7\r\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "strong.csv"
            path.write_text(content, encoding="utf-8")
            result = audit_csv(path)

        self.assertEqual(result["kind"], "strong_csv")
        self.assertTrue(result["weight_unit_confirmation_required"])
        self.assertEqual(result["set_index_base_candidate"], 1)
        self.assertNotIn("Private Workout", json.dumps(result))
        self.assertNotIn("Private Exercise", json.dumps(result))
        self.assertNotIn("private note", json.dumps(result))

    def test_hevy_variants_are_detected_by_headers(self):
        content = (
            "title,start_time,end_time,description,exercise_title,set_index,set_type,weight_kg,reps,distance_meters,duration_seconds,rpe,exercise_notes\n"
            "private,2026-08-01 10:00:00,2026-08-01 11:00:00,,private,0,warmup,20,10,,,5,\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hevy.csv"
            path.write_text(content, encoding="utf-8")
            result = audit_file(path)

        self.assertEqual(result["kind"], "hevy_workout_csv")
        self.assertEqual(result["set_index_base_candidate"], 0)
        self.assertEqual(result["set_types"], {"warmup": 1})
        self.assertTrue(result["timezone_missing"])
        self.assertIn("weight_kg", result["unit_columns"])

    def test_localized_english_date_without_offset_requires_timezone_confirmation(self):
        content = (
            "title,start_time,end_time,exercise_title,set_index,set_type,weight_kg,reps\n"
            'private,"August 1, 2026 10:00","August 1, 2026 11:00",private,1,normal,20,10\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hevy-localized.csv"
            path.write_text(content, encoding="utf-8")
            result = audit_csv(path)

        self.assertTrue(result["timezone_missing"])
        self.assertEqual(result["date_formats"], {"english_month": 2})

    def test_hevy_day_first_english_date_is_recognized_without_timezone(self):
        content = (
            "title,start_time,end_time,exercise_title,set_index,set_type,weight_kg,reps\n"
            'private,"30 Jun 2025, 19:56","30 Jun 2025, 20:58",private,0,normal,20,10\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "hevy-day-first.csv"
            path.write_text(content, encoding="utf-8")
            result = audit_csv(path)

        self.assertTrue(result["timezone_missing"])
        self.assertEqual(result["date_formats"], {"day_english_month": 2})

    def test_bodymode_json_reports_only_structure_and_counts(self):
        payload = {"schemaVersion": 6, "workoutHistory": [{"title": "private"}], "bodyPhotos": []}
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "bodymode.json"
            path.write_text(json.dumps(payload), encoding="utf-8")
            result = audit_json(path)

        self.assertEqual(result["kind"], "bodymode_json")
        self.assertEqual(result["schema_version"], 6)
        self.assertEqual(result["collection_counts"]["workoutHistory"], 1)
        self.assertNotIn("private", json.dumps(result))


if __name__ == "__main__":
    unittest.main()

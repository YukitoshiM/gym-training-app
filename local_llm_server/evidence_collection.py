from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class EvidenceCollectionQuery:
    identifier: str
    goals: tuple[str, ...]
    topic: str
    subtopic: str
    query: str


QUALITY_FILTER = (
    '(META_ANALYSIS:y OR "systematic review" OR "randomized controlled trial" '
    'OR "clinical trial" OR guideline OR "consensus statement" OR review)'
)


def _query(
    identifier: str,
    goals: tuple[str, ...],
    topic: str,
    subtopic: str,
    subject: str,
) -> EvidenceCollectionQuery:
    return EvidenceCollectionQuery(
        identifier=identifier,
        goals=goals,
        topic=topic,
        subtopic=subtopic,
        query=f"SRC:MED AND HAS_ABSTRACT:y AND ({subject}) AND {QUALITY_FILTER}",
    )


EVIDENCE_COLLECTION_PLAN = (
    # Hypertrophy
    _query("hyp_volume", ("hypertrophy", "body_recomposition"), "hypertrophy", "training_volume", 'TITLE_ABS:("resistance training" AND (hypertrophy OR "muscle growth") AND (volume OR sets))'),
    _query("hyp_frequency", ("hypertrophy",), "hypertrophy", "training_frequency", 'TITLE_ABS:("resistance training" AND hypertrophy AND frequency)'),
    _query("hyp_load", ("hypertrophy",), "hypertrophy", "loading", 'TITLE_ABS:("resistance training" AND hypertrophy AND (load OR intensity OR repetition))'),
    _query("hyp_failure", ("hypertrophy",), "hypertrophy", "proximity_to_failure", 'TITLE_ABS:("resistance training" AND (failure OR "repetitions in reserve" OR RIR) AND (hypertrophy OR muscle))'),
    _query("hyp_rest", ("hypertrophy",), "hypertrophy", "rest_intervals", 'TITLE_ABS:("resistance training" AND "rest interval" AND (hypertrophy OR muscle))'),
    _query("hyp_rom", ("hypertrophy",), "hypertrophy", "range_of_motion", 'TITLE_ABS:("resistance training" AND "range of motion" AND (hypertrophy OR muscle))'),
    _query("hyp_tempo", ("hypertrophy",), "hypertrophy", "tempo", 'TITLE_ABS:("resistance training" AND (tempo OR "movement velocity" OR "repetition duration") AND hypertrophy)'),
    _query("hyp_selection", ("hypertrophy",), "hypertrophy", "exercise_selection", 'TITLE_ABS:("resistance exercise" AND ("exercise selection" OR "single joint" OR "multi joint") AND hypertrophy)'),
    _query("hyp_protein", ("hypertrophy", "body_recomposition"), "protein", "protein_dose", 'TITLE_ABS:((protein OR "amino acid") AND ("resistance training" OR hypertrophy OR "muscle mass"))'),
    _query("hyp_energy", ("hypertrophy", "body_recomposition"), "hypertrophy", "energy_balance", 'TITLE_ABS:(("energy surplus" OR "energy balance" OR calorie) AND (hypertrophy OR "muscle mass" OR "resistance training"))'),

    # Strength
    _query("str_load", ("strength",), "strength", "loading", 'TITLE_ABS:("resistance training" AND strength AND (load OR intensity OR repetition))'),
    _query("str_volume", ("strength",), "strength", "training_volume", 'TITLE_ABS:("resistance training" AND strength AND (volume OR sets))'),
    _query("str_frequency", ("strength",), "strength", "training_frequency", 'TITLE_ABS:("resistance training" AND strength AND frequency)'),
    _query("str_periodization", ("strength", "athletic_performance"), "strength", "periodization", 'TITLE_ABS:((periodization OR periodisation) AND (strength OR "resistance training"))'),
    _query("str_autoregulation", ("strength", "athletic_performance"), "strength", "autoregulation", 'TITLE_ABS:((autoregulation OR "rating of perceived exertion" OR "repetitions in reserve") AND "resistance training")'),
    _query("str_velocity", ("strength", "athletic_performance"), "strength", "velocity_based_training", 'TITLE_ABS:("velocity based training" AND (strength OR power OR athlete))'),

    # Fat loss
    _query("fat_deficit", ("fat_loss",), "fat_loss", "energy_deficit", 'TITLE_ABS:(("energy restriction" OR "caloric restriction" OR "energy deficit") AND ("weight loss" OR "fat loss" OR obesity))'),
    _query("fat_rate", ("fat_loss",), "fat_loss", "rate_of_loss", 'TITLE_ABS:(("rate of weight loss" OR "weight loss rate") AND (muscle OR "lean mass" OR athlete))'),
    _query("fat_resistance", ("fat_loss", "body_recomposition"), "fat_loss", "lean_mass_preservation", 'TITLE_ABS:(("weight loss" OR "energy restriction") AND "resistance training" AND ("lean mass" OR muscle OR "body composition"))'),
    _query("fat_protein", ("fat_loss", "body_recomposition"), "protein", "satiety_and_lean_mass", 'TITLE_ABS:(("high protein" OR "protein intake") AND ("weight loss" OR "energy restriction" OR satiety))'),
    _query("fat_aerobic", ("fat_loss",), "fat_loss", "aerobic_activity", 'TITLE_ABS:((aerobic OR cardio OR "physical activity") AND ("fat loss" OR "weight loss" OR "fat mass"))'),
    _query("fat_steps", ("fat_loss", "wellness"), "fat_loss", "steps_and_neat", 'TITLE_ABS:((steps OR walking OR "non-exercise activity") AND ("weight loss" OR obesity OR "body composition"))'),
    _query("fat_adherence", ("fat_loss",), "fat_loss", "diet_adherence", 'TITLE_ABS:((adherence OR maintenance) AND (diet OR "weight loss") AND (obesity OR overweight))'),
    _query("fat_sleep", ("fat_loss",), "sleep_recovery", "sleep_and_weight", 'TITLE_ABS:(sleep AND ("weight loss" OR obesity OR "body composition" OR "energy intake"))'),

    # Body recomposition
    _query("rec_concurrent", ("body_recomposition",), "fat_loss", "concurrent_change", 'TITLE_ABS:(("body recomposition" OR "body composition") AND "resistance training" AND (diet OR protein OR "fat mass"))'),
    _query("rec_deficit", ("body_recomposition",), "protein", "protein_during_deficit", 'TITLE_ABS:((protein OR "amino acid") AND "energy deficit" AND ("lean mass" OR muscle))'),
    _query("rec_combined", ("body_recomposition",), "fat_loss", "combined_training", 'TITLE_ABS:(("combined training" OR "concurrent training") AND ("body composition" OR "fat mass" OR "lean mass"))'),
    _query("rec_waist", ("body_recomposition", "wellness"), "fat_loss", "waist_circumference", 'TITLE_ABS:((exercise OR "physical activity") AND "waist circumference")'),
    _query("rec_population", ("body_recomposition",), "hypertrophy", "training_status", 'TITLE_ABS:((novice OR beginner OR trained) AND "resistance training" AND "body composition")'),

    # General health and wellness
    _query("wel_guidelines", ("wellness",), "wellness", "activity_guidelines", 'TITLE_ABS:(("physical activity guideline" OR "exercise guideline") AND health)'),
    _query("wel_steps", ("wellness",), "wellness", "daily_steps", 'TITLE_ABS:(("daily steps" OR "step count" OR walking) AND (health OR mortality OR cardiovascular))'),
    _query("wel_resistance", ("wellness",), "wellness", "resistance_training_health", 'TITLE_ABS:("resistance training" AND (health OR mortality OR cardiovascular OR metabolic))'),
    _query("wel_aerobic", ("wellness",), "wellness", "aerobic_health", 'TITLE_ABS:((aerobic OR "cardiorespiratory fitness") AND (health OR mortality OR cardiovascular))'),
    _query("wel_sleep", ("wellness",), "sleep_recovery", "sleep_health", 'TITLE_ABS:(sleep AND (health OR wellbeing OR "well-being" OR mortality))'),
    _query("wel_older", ("wellness", "return_to_training"), "wellness", "older_adults", 'TITLE_ABS:(("older adults" OR elderly) AND (exercise OR "physical activity" OR "resistance training") AND health)'),
    _query("wel_sedentary", ("wellness",), "wellness", "sedentary_behavior", 'TITLE_ABS:((sedentary OR "sitting time") AND (exercise OR "physical activity") AND health)'),

    # Athletic performance and recovery
    _query("ath_concurrent", ("athletic_performance",), "strength", "concurrent_training", 'TITLE_ABS:("concurrent training" AND (strength OR endurance OR performance OR athlete))'),
    _query("ath_plyometric", ("athletic_performance",), "strength", "plyometrics", 'TITLE_ABS:((plyometric OR jump) AND training AND (performance OR athlete OR power))'),
    _query("ath_sprint", ("athletic_performance",), "strength", "sprint_training", 'TITLE_ABS:(sprint AND training AND (performance OR athlete OR speed))'),
    _query("ath_power", ("athletic_performance",), "strength", "power_training", 'TITLE_ABS:(("power training" OR "ballistic training" OR "Olympic weightlifting") AND performance)'),
    _query("ath_periodization", ("athletic_performance",), "strength", "periodization", 'TITLE_ABS:((periodization OR periodisation) AND (athlete OR sport OR performance))'),
    _query("ath_readiness", ("athletic_performance",), "fatigue", "readiness_monitoring", 'TITLE_ABS:((readiness OR fatigue OR HRV OR "heart rate variability") AND (athlete OR training) AND monitoring)'),
    _query("ath_recovery", ("athletic_performance",), "sleep_recovery", "recovery", 'TITLE_ABS:((sleep OR recovery) AND (athlete OR sport) AND performance)'),

    # Return to training. These inform conservative exercise guidance, not diagnosis.
    _query("ret_sport", ("return_to_training",), "return_to_training", "return_to_sport", 'TITLE_ABS:(("return to sport" OR "return to training") AND (exercise OR rehabilitation OR athlete))'),
    _query("ret_detraining", ("return_to_training",), "return_to_training", "detraining_retraining", 'TITLE_ABS:((detraining OR retraining) AND (strength OR muscle OR exercise OR athlete))'),
    _query("ret_graded", ("return_to_training",), "return_to_training", "graded_loading", 'TITLE_ABS:(("graded exercise" OR "graded loading" OR "progressive loading") AND (return OR rehabilitation OR training))'),
    _query("ret_load", ("return_to_training", "athletic_performance"), "fatigue", "load_management", 'TITLE_ABS:(("training load" OR "load management") AND (injury OR recovery OR "return to sport"))'),
    _query("ret_inactivity", ("return_to_training", "wellness"), "return_to_training", "physical_inactivity", 'TITLE_ABS:(("physical inactivity" OR deconditioning) AND (retraining OR exercise OR recovery))'),
)


SUPPORTED_EVIDENCE_GOALS = tuple(
    sorted({goal for item in EVIDENCE_COLLECTION_PLAN for goal in item.goals})
)


def collection_text_matches(identifier: str, title: str, abstract: str) -> bool | None:
    """Return a special-purpose match, or None to use the general topic filter."""
    title_value = title.lower()
    text = f"{title} {abstract}".lower()
    special_rules = {
        "ret_detraining": (
            ("detraining", "retraining", "training cessation"),
            ("strength", "muscle", "exercise", "training", "physical performance"),
        ),
        "ret_graded": (
            ("graded exercise", "graded loading", "progressive loading"),
            ("training", "exercise", "rehabilitation", "return"),
        ),
        "ret_load": (
            ("training load", "load management"),
            ("injury", "recovery", "return to sport"),
        ),
        "ret_inactivity": (
            ("physical inactivity", "deconditioning"),
            ("exercise", "training", "retraining", "recovery"),
        ),
    }
    groups = special_rules.get(identifier)
    if not groups:
        return None
    return any(term in title_value for term in groups[0]) and any(
        term in text for term in groups[1]
    )

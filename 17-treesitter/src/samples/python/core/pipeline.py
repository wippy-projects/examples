from loader import load_csv, load_json
from transformer import transform_records
from validator import validate_batch
from reporter import generate_report


def run_pipeline(config):
    raw = load_data(config)
    transformed = transform_records(raw)
    valid = validate_batch(transformed)
    report = generate_report(valid)
    return report


def load_data(config):
    source = config.get("source", "csv")
    if source == "csv":
        return load_csv(config["input_path"])
    return load_json(config["input_path"])

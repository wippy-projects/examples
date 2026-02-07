from pipeline import run_pipeline
from config import load_config
from logger_util import setup_logger


def main():
    config = load_config()
    logger = setup_logger(config)
    result = run_pipeline(config)
    print_summary(result)


def print_summary(result):
    count = len(result)
    print(f"Processed {count} records")


main()

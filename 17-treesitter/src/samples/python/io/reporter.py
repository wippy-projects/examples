from formatter import format_table, format_percentage
from logger_util import log_info


def generate_report(records):
    log_info(f"Generating report for {len(records)} records")
    stats = compute_stats(records)
    table = format_table(stats)
    return build_output(table, stats)


def compute_stats(records):
    total = len(records)
    return {"total": total, "rate": format_percentage(total, 100)}


def build_output(table, stats):
    return {"table": table, "stats": stats}

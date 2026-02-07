from logger_util import log_info, log_warning


def validate_batch(records):
    log_info(f"Validating {len(records)} records")
    valid = []
    for record in records:
        if validate_record(record):
            valid.append(record)
        else:
            log_warning(f"Invalid record: {record}")
    return valid


def validate_record(record):
    return check_required(record) and check_format(record)


def check_required(record):
    return record is not None


def check_format(record):
    return len(str(record)) > 0

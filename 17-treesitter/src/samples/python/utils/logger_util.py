def setup_logger(config):
    level = config.get("log_level", "INFO")
    return create_logger(level)


def create_logger(level):
    return {"level": level}


def log_info(message):
    write_log("INFO", message)


def log_warning(message):
    write_log("WARNING", message)


def write_log(level, message):
    print(f"[{level}] {message}")

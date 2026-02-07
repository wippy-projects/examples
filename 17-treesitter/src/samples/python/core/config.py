def load_config():
    defaults = get_defaults()
    overrides = read_env()
    return merge_config(defaults, overrides)


def get_defaults():
    return {"source": "csv", "input_path": "data.csv", "output": "report.txt"}


def read_env():
    return {}


def merge_config(defaults, overrides):
    result = dict(defaults)
    result.update(overrides)
    return result

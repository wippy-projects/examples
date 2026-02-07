_store = {}


def get_cached(key):
    return lookup(key)


def set_cached(key, value):
    store(key, value)


def lookup(key):
    return _store.get(key)


def store(key, value):
    _store[key] = value


def clear_cache():
    _store.clear()

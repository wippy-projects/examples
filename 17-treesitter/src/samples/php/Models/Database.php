<?php

class Database {
    public static function connect() {
        return new Database();
    }

    public function query($sql, $params = []) {
        return logQuery($sql, $params);
    }

    public function execute($sql, $params = []) {
        return logQuery($sql, $params);
    }
}

function logQuery($sql, $params) {
    return ['sql' => $sql, 'params' => $params];
}

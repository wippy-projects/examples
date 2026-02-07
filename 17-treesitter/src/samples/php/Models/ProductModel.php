<?php

class ProductModel {
    public function findAll() {
        $db = Database::connect();
        return $db->query('SELECT * FROM products');
    }

    public function findById($id) {
        $db = Database::connect();
        return $db->query('SELECT * FROM products WHERE id = ?', [$id]);
    }

    public function insert($data) {
        $db = Database::connect();
        return $db->execute('INSERT INTO products (name, price) VALUES (?, ?)', [$data]);
    }
}

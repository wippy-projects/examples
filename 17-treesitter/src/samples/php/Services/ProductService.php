<?php

class ProductService {
    public function getAllProducts() {
        $model = new ProductModel();
        $products = $model->findAll();
        return formatProducts($products);
    }

    public function createProduct($data) {
        $validated = validateProductData($data);
        $model = new ProductModel();
        return $model->insert($validated);
    }

    public function findProduct($id) {
        $model = new ProductModel();
        return $model->findById($id);
    }
}

function formatProducts($products) {
    return $products;
}

function validateProductData($data) {
    return $data;
}

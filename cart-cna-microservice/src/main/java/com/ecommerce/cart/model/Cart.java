package com.ecommerce.cart.model;

import java.util.ArrayList;
import java.util.List;
import java.util.Optional;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.Getter;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
@Getter
public class Cart {
    private String customerId;
    private List<CartItem> items = new ArrayList<>();
    private float total;
    private String currency = "USD";
    private long lastUpdated;
    private int version = 1;
    
    public Cart(String customerId) {
        this.customerId = customerId;
        this.items = new ArrayList<>();
        this.currency = "USD";
        this.lastUpdated = System.currentTimeMillis();
        this.total = 0.0f;
    }
    
    public void addItem(CartItem item) {
        if (item == null || item.getProductId() == null) {
            throw new IllegalArgumentException("Item and product ID cannot be null");
        }
        
        Optional<CartItem> existingItem = items.stream()
            .filter(i -> i.getProductId().equals(item.getProductId()))
            .findFirst();
            
        if (existingItem.isPresent()) {
            CartItem existing = existingItem.get();
            existing.setQuantity(existing.getQuantity() + item.getQuantity());
        } else {
            items.add(item);
        }
        
        recalculateTotal();
        this.lastUpdated = System.currentTimeMillis();
    }
    
    public void removeItem(String productId) {
        if (productId == null) {
            throw new IllegalArgumentException("Product ID cannot be null");
        }
        
        items.removeIf(item -> productId.equals(item.getProductId()));
        recalculateTotal();
        this.lastUpdated = System.currentTimeMillis();
    }
    
    public void updateItemQuantity(String productId, int quantity) {
        if (productId == null) {
            throw new IllegalArgumentException("Product ID cannot be null");
        }
        
        if (quantity <= 0) {
            removeItem(productId);
            return;
        }
        
        Optional<CartItem> item = items.stream()
            .filter(i -> i.getProductId().equals(productId))
            .findFirst();
            
        if (item.isPresent()) {
            item.get().setQuantity(quantity);
            recalculateTotal();
            this.lastUpdated = System.currentTimeMillis();
        }
    }
    
    public void clear() {
        items.clear();
        total = 0.0f;
        this.lastUpdated = System.currentTimeMillis();
    }
    
    public int getItemCount() {
        return items.stream().mapToInt(CartItem::getQuantity).sum();
    }
    
    public boolean isEmpty() {
        return items.isEmpty();
    }
    
    private void recalculateTotal() {
        this.total = items.stream()
            .map(item -> item.getPrice() * item.getQuantity())
            .reduce(0.0f, Float::sum);
    }
}

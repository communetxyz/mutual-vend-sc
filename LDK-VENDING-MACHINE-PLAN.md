# LDK Lightning Vending Machine Daemon

A standalone Rust daemon implementing vending machine functionality with Bitcoin Lightning Network payments using [ldk-node](https://github.com/lightningdevkit/ldk-node).

## Overview

This project is a "fork" of the Solidity-based [mutual-vend-sc](https://github.com/lightningdevkit/rust-lightning) vending machine, reimagined for Bitcoin's Lightning Network instead of EVM stablecoins.

**Key differences from original:**
- Payments in Bitcoin (satoshis) via Lightning instead of USDC/USDT/DAI
- Rust application instead of Solidity smart contracts
- Off-chain payments with instant settlement
- Self-custodial Lightning node

## Requirements

- **LDK-based**: Uses `ldk-node` high-level wrapper around rust-lightning
- **Minimal core logic**: Products, tracks, inventory, payment flow
- **Standalone daemon**: Server application with REST API
- **Self-custodial**: Operator runs their own Lightning node

## Project Structure

```
lightning-vending-machine/
├── Cargo.toml
├── config/
│   ├── default.toml           # Default configuration
│   └── testnet.toml           # Bitcoin testnet settings
├── data/                      # Runtime data (gitignored)
│   ├── ldk/                   # LDK node data
│   └── vending.db             # SQLite database
├── src/
│   ├── main.rs                # Entry point, CLI parsing
│   ├── lib.rs                 # Library root
│   ├── config.rs              # Configuration loading
│   ├── node/
│   │   ├── mod.rs             # Lightning node wrapper
│   │   └── setup.rs           # Node initialization
│   ├── vending/
│   │   ├── mod.rs             # Vending machine core
│   │   ├── inventory.rs       # Track/product management
│   │   └── invoice.rs         # Invoice lifecycle
│   ├── persistence/
│   │   ├── mod.rs             # Database abstraction
│   │   └── sqlite.rs          # SQLite implementation
│   ├── api/
│   │   ├── mod.rs             # REST API module
│   │   ├── rest.rs            # Axum router
│   │   └── handlers.rs        # Request handlers
│   └── events/
│       ├── mod.rs             # Event handling
│       └── processor.rs       # LDK event processor
└── tests/
    └── integration/           # Integration tests
```

## Dependencies

```toml
[package]
name = "lightning-vending-machine"
version = "0.1.0"
edition = "2021"
rust-version = "1.85.0"

[dependencies]
# LDK Node - High-level Lightning node abstraction
ldk-node = "0.4"

# Async runtime
tokio = { version = "1", features = ["full"] }

# Web API framework
axum = "0.7"
tower-http = { version = "0.5", features = ["cors", "trace"] }

# Serialization
serde = { version = "1", features = ["derive"] }
serde_json = "1"
toml = "0.8"

# Database
rusqlite = { version = "0.32", features = ["bundled"] }

# CLI
clap = { version = "4", features = ["derive"] }

# Logging
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }

# Error handling
thiserror = "1"
anyhow = "1"

# Utilities
chrono = { version = "0.4", features = ["serde"] }
uuid = { version = "1", features = ["v4", "serde"] }
```

## Core Data Structures

Mirroring the original Solidity VendingMachine concepts:

```rust
/// Product information (mirrors IVendingMachine.Product)
pub struct Product {
    pub name: String,
    pub image_uri: String,
}

/// Track information (mirrors IVendingMachine.Track)
pub struct Track {
    pub track_id: u8,
    pub product: Product,
    pub price_sats: u64,  // Price in satoshis (not wei)
    pub stock: u32,
}

/// Invoice tracking for pending payments
pub struct PendingInvoice {
    pub id: Uuid,
    pub track_id: u8,
    pub bolt11: String,
    pub payment_hash: String,
    pub amount_sats: u64,
    pub created_at: DateTime<Utc>,
    pub expires_at: DateTime<Utc>,
    pub status: InvoiceStatus,
}

pub enum InvoiceStatus {
    Pending,
    Paid,
    Expired,
}

/// Purchase record (similar to ItemVended event)
pub struct Purchase {
    pub id: Uuid,
    pub track_id: u8,
    pub payment_hash: String,
    pub amount_sats: u64,
    pub completed_at: DateTime<Utc>,
}
```

## Purchase Flow

```
┌────────────────────────────────────────────────────────────────────┐
│                         PURCHASE FLOW                               │
└────────────────────────────────────────────────────────────────────┘

1. REQUEST INVOICE
   Client ──POST /api/v1/purchase/{track_id}──> API Handler
                                                    │
                                                    ▼
   ┌─────────────────────────────────────────────────────────────┐
   │ InvoiceManager.create_purchase_invoice()                    │
   │  ├─ Validate track exists                                   │
   │  ├─ Validate stock > 0                                      │
   │  ├─ Create BOLT11 invoice via ldk-node                      │
   │  └─ Return invoice to client                                │
   └─────────────────────────────────────────────────────────────┘
                                                    │
   Client <──JSON { bolt11, payment_hash, amount_sats }──

2. PAYMENT (User pays via Lightning wallet)
   User Wallet ──Lightning Payment──> LDK Node
                                          │
                                          ▼
                                   PaymentReceived Event

3. EVENT PROCESSING
   ┌─────────────────────────────────────────────────────────────┐
   │ EventProcessor.handle_event(PaymentReceived)                │
   │  ├─ Lookup PendingInvoice by payment_hash                   │
   │  ├─ Mark invoice as Paid                                    │
   │  ├─ Decrement track stock                                   │
   │  ├─ Record Purchase                                         │
   │  └─ Trigger dispense signal                                 │
   └─────────────────────────────────────────────────────────────┘
                                          │
                                          ▼
                               [Hardware: DISPENSE]

4. STATUS CHECK (Client polls)
   Client ──GET /api/v1/invoice/{payment_hash}──> API Handler
   Client <──JSON { status: "Paid", paid: true }──
```

## REST API

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/api/v1/tracks` | List all tracks with products and stock |
| `GET` | `/api/v1/tracks/:id` | Get single track details |
| `POST` | `/api/v1/purchase/:track_id` | Create Lightning invoice for purchase |
| `GET` | `/api/v1/invoice/:payment_hash` | Check invoice/payment status |
| `GET` | `/api/v1/node/info` | Get node public key and info |
| `GET` | `/health` | Health check |

### Example: Create Purchase Invoice

```bash
curl -X POST http://localhost:8080/api/v1/purchase/0
```

Response:
```json
{
  "bolt11": "lntb50u1pj...",
  "payment_hash": "abc123...",
  "amount_sats": 5000,
  "expires_at": "2024-01-15T12:00:00Z"
}
```

### Example: Check Payment Status

```bash
curl http://localhost:8080/api/v1/invoice/abc123
```

Response:
```json
{
  "status": "Paid",
  "paid": true
}
```

## Configuration

```toml
# config/testnet.toml

[node]
network = "testnet"
esplora_url = "https://blockstream.info/testnet/api"
rgs_url = "https://rapidsync.lightningdevkit.org/testnet/snapshot"
listening_port = 9735
data_dir = "./data/ldk"

[vending]
num_tracks = 3
max_stock_per_track = 10

[[vending.products]]
name = "Coca Cola"
description = "Refreshing cola beverage"
image_uri = "ipfs://QmCocaCola"
stock = 10
price_sats = 5000  # ~$5 at $100k/BTC

[[vending.products]]
name = "Water"
description = "Pure spring water"
stock = 10
price_sats = 2500

[[vending.products]]
name = "Energy Drink"
description = "High caffeine energy"
stock = 5
price_sats = 10000

[api]
host = "0.0.0.0"
port = 8080

[persistence]
database_path = "./data/vending.db"
```

## Implementation Order

### Phase 1: Project Setup
1. Initialize Rust project with Cargo.toml
2. Set up directory structure
3. Implement configuration loading
4. Basic logging infrastructure

### Phase 2: Persistence Layer
1. SQLite schema for tracks, invoices, purchases
2. Database abstraction layer
3. CRUD operations

### Phase 3: Lightning Node
1. `LightningNode` wrapper around ldk-node
2. Node initialization with testnet config
3. Invoice creation via `bolt11_payment().receive()`
4. Event loop setup

### Phase 4: Vending Logic
1. `Inventory` manager for tracks/products
2. `InvoiceManager` for invoice lifecycle
3. Stock management with atomic operations

### Phase 5: Event Processing
1. `EventProcessor` for LDK events
2. Handle `PaymentReceived` events
3. Connect payments to inventory decrements
4. Dispense trigger (hardware integration point)

### Phase 6: REST API
1. Axum web server setup
2. Track/product endpoints
3. Purchase (invoice creation) endpoint
4. Invoice status endpoint
5. CORS and error handling

### Phase 7: Testing & Polish
1. Integration tests with regtest
2. Error handling improvements
3. Invoice expiration cleanup
4. Graceful shutdown
5. Documentation

## Hardware Integration

The `EventProcessor.trigger_dispense()` method is the integration point:

```rust
async fn trigger_dispense(&self, track_id: u8) -> Result<()> {
    // Option 1: HTTP webhook to hardware controller
    // client.post("http://localhost:5000/dispense").json(&track_id).send().await?;

    // Option 2: GPIO via rppal (Raspberry Pi)
    // let gpio = Gpio::new()?;
    // let mut pin = gpio.get(TRACK_PINS[track_id])?.into_output();
    // pin.set_high();

    // Option 3: Serial/UART to microcontroller
    // serial_port.write(&[0x01, track_id])?;

    tracing::info!("DISPENSE signal for track {}", track_id);
    Ok(())
}
```

## Security Considerations

1. **Seed Protection**: Store mnemonic/entropy encrypted at rest
2. **API Rate Limiting**: Prevent invoice spam
3. **Payment Verification**: Always verify payment_hash matches expected invoice
4. **Stock Atomicity**: Use atomic operations for stock decrements
5. **Invoice Single-Use**: Each invoice is single-use (enforced by Lightning)

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| LDK abstraction | `ldk-node` | Higher-level API, handles sync/persistence |
| Persistence | SQLite | Simple, embedded, sufficient for vending scale |
| API framework | Axum | Modern, async-first, good performance |
| Price unit | Satoshis | Native Lightning unit, avoids floating point |
| Invoice expiry | 1 hour | Balance between UX and resource usage |

## References

- [rust-lightning](https://github.com/lightningdevkit/rust-lightning) - Core Lightning implementation
- [ldk-node](https://github.com/lightningdevkit/ldk-node) - High-level node wrapper
- [LDK Documentation](https://lightningdevkit.org/)
- [BOLT Specifications](https://github.com/lightning/bolts) - Lightning protocol specs

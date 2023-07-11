pub trait NovaCircuitInput {
    fn circuit_input(&self) -> std::collections::HashMap<String, serde_json::Value>;
}

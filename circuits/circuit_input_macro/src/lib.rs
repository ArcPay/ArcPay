pub trait NovaRoundInput {
    fn circuit_input(&self) -> std::collections::HashMap<String, serde_json::Value>;
}

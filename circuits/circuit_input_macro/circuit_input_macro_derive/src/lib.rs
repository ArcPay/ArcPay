use proc_macro::TokenStream;
use quote::quote;
use syn;

#[proc_macro_derive(NovaCircuitInput)]
pub fn circuit_input_macro_derive(input: TokenStream) -> TokenStream {
    let ast = syn::parse(input).unwrap();
    impl_circuit_input_macro(&ast)
}

fn impl_circuit_input_macro(ast: &syn::DeriveInput) -> TokenStream {
    let name = &ast.ident;
    let fields = if let syn::Data::Struct(syn::DataStruct {
        fields: syn::Fields::Named(syn::FieldsNamed { named, .. }),
        ..
    }) = ast.data.clone()
    {
        named
    } else {
        unimplemented!()
    };

    let insertions = fields.iter().map(|f| {
        let name = f.ident.as_ref().unwrap();
        quote! {
            map.insert(
                stringify!(#name).to_string(),
                ::serde_json::json!(self.#name)
            );
        }
    });

    let gen = quote! {
        impl NovaCircuitInput for #name {
            fn circuit_input(&self) -> std::collections::HashMap<String, serde_json::Value> {
                let mut map = std::collections::HashMap::new();
                #(#insertions)*
                map
            }
        }
    };
    gen.into()
}

import streamlit as st
import pandas as pd
import joblib

artifact = joblib.load(
    "model_artifacts/late_delivery_model.joblib"
)

model = artifact["model"]
feature_cols = artifact["features"]

st.title("Olist Late Delivery Prediction")
st.write("Estimate the probability of a late delivery.")

with st.form("prediction_form"):
    state = st.selectbox(
        "Customer state",
        ["SP", "RJ", "MG", "RS", "PR", "Other"]
    )

    month = st.slider("Purchase month", 1, 12, 10)
    day = st.selectbox("Day of week", list(range(7)))
    hour = st.slider("Purchase hour", 0, 23, 14)

    estimated_days = st.number_input(
        "Estimated delivery days", min_value=0.0, value=12.0
    )

    item_count = st.number_input(
        "Number of items", min_value=1, value=2
    )

    item_value = st.number_input(
        "Item value", min_value=0.0, value=250.0
    )

    freight = st.number_input(
        "Freight value", min_value=0.0, value=35.0
    )

    seller_count = st.number_input(
        "Number of sellers", min_value=1, value=1
    )

    product_count = st.number_input(
        "Number of unique products", min_value=1, value=2
    )

    submitted = st.form_submit_button("Predict")

if submitted:
    new_order = pd.DataFrame([{
        "customer_state": state,
        "purchase_month": month,
        "purchase_day_of_week": day,
        "purchase_hour": hour,
        "estimated_delivery_days": estimated_days,
        "item_count": item_count,
        "item_value": item_value,
        "freight_value": freight,
        "seller_count": seller_count,
        "product_count": product_count
    }])[feature_cols]

    probability = model.predict_proba(new_order)[0, 1]

    st.metric(
        "Estimated late-delivery probability",
        f"{probability:.1%}"
    )
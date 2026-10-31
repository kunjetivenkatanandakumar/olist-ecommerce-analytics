"""
Olist E-commerce Analytics (Streamlit).

A faithful rebuild of ecom.pbix: same five pages, same slicers, cards and
charts, same chart types and Top 10 filters, and the same page navigation.

Files expected next to app.py:
  - Data/ folder with the CSV files   OR   Data.zip
  - olist_banner.png (optional, header image used on every page)

Run locally:  streamlit run app.py
"""

import hmac
import zipfile
from pathlib import Path

import joblib
import pandas as pd
import plotly.express as px
import streamlit as st

st.set_page_config(
    page_title="Olist E-commerce Analytics",
    page_icon="🛒",
    layout="wide",
    initial_sidebar_state="collapsed",
)

BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "Data"
DATA_ZIP = BASE_DIR / "Data.zip"
BANNER = BASE_DIR / "olist_banner.png"

# Colours from the report's "Frontier" theme
COLORS = [
    "#426871", "#D2B04C", "#A3623A", "#C25A3D", "#C39B6A", "#016E51",
    "#998F85", "#FFA500", "#87ACB6", "#B8A901", "#FDB15D", "#F48459",
]
BACKGROUND = "#F9F7F2"

PAGES = ["Orders Overview", "Reviews & Satisfaction", "Customer Analytics",
         "Payments Analysis", "Seller Performance"]

ORDER_DATE_COLUMNS = [
    "order_purchase_timestamp", "order_approved_at", "order_delivered_carrier_date",
    "order_delivered_customer_date", "order_estimated_delivery_date",
]

st.markdown(
    f"""
    <style>
      .stApp {{ background-color: {BACKGROUND}; }}
      h1 {{ font-weight: 700; }}
      div[data-testid="stMetricValue"] {{ font-size: 1.9rem; }}
    </style>
    """,
    unsafe_allow_html=True,
)


# ============================================================ data loading
def read_csv(filename: str) -> pd.DataFrame:
    """Read a CSV from the Data/ folder, or from inside Data.zip."""
    path = DATA_DIR / filename
    if path.exists():
        return pd.read_csv(path, low_memory=False)
    if DATA_ZIP.exists():
        with zipfile.ZipFile(DATA_ZIP) as zf:
            member = next((n for n in zf.namelist() if n.split("/")[-1] == filename), None)
            if member is not None:
                with zf.open(member) as fh:
                    return pd.read_csv(fh, low_memory=False)
    raise FileNotFoundError(
        f"'{filename}' was not found. Place the Data/ folder or Data.zip next to app.py."
    )


def parse_dates(series: pd.Series) -> pd.Series:
    """Dates mix M/D/YYYY strings with DD-MM-YYYY strings; parse both correctly."""
    text = series.astype("string").str.strip()
    day_first = text.str.match(r"^\d{2}-\d{2}-\d{4}", na=False)
    month_first = pd.to_datetime(text.where(~day_first), format="mixed", errors="coerce")
    dash_dates = pd.to_datetime(text.where(day_first), format="mixed", dayfirst=True, errors="coerce")
    return month_first.fillna(dash_dates)


@st.cache_data(show_spinner="Loading Olist data...")
def load_data() -> dict:
    customers = read_csv("Customer.csv")
    orders = read_csv("orders.csv")
    items = read_csv("order_items.csv")
    payments = read_csv("order_payments.csv")
    reviews = read_csv("order_reviews.csv")
    products = read_csv("products.csv")
    sellers = read_csv("sellers.csv")
    translation = read_csv("product_category_name_translation.csv")

    for col in ORDER_DATE_COLUMNS:
        orders[col] = parse_dates(orders[col])
    items["shipping_limit_date"] = parse_dates(items["shipping_limit_date"])
    reviews["review_creation_date"] = parse_dates(reviews["review_creation_date"])
    reviews["review_answer_timestamp"] = parse_dates(reviews["review_answer_timestamp"])

    products = products.merge(translation, on="product_category_name", how="left")
    products["category"] = (
        products["product_category_name_english"]
        .fillna(products["product_category_name"])
        .fillna("unknown")
    )

    # Orders: customer attributes plus year fields used by the slicers
    orders = orders.merge(
        customers[["customer_id", "customer_unique_id", "customer_zip_code_prefix",
                   "customer_city", "customer_state"]],
        on="customer_id", how="left",
    )
    orders["year"] = orders["order_purchase_timestamp"].dt.year       # orders.Year / or_pr_Year
    orders["del_year"] = orders["order_delivered_customer_date"].dt.year  # orders.del_year
    orders["is_delivered"] = orders["order_status"].eq("delivered")

    # Items: product category, seller state, and the order's year and state
    items = items.merge(products[["product_id", "category"]], on="product_id", how="left")
    items = items.merge(sellers[["seller_id", "seller_state"]], on="seller_id", how="left")
    items["category"] = items["category"].fillna("unknown")
    order_lookup = orders.set_index("order_id")
    items["year"] = items["order_id"].map(order_lookup["year"])
    items["customer_state"] = items["order_id"].map(order_lookup["customer_state"])

    # Reviews: review year for the slicer
    reviews["review_year"] = reviews["review_creation_date"].dt.year

    return {"orders": orders, "items": items, "payments": payments, "reviews": reviews,
            "products": products, "sellers": sellers}


# ============================================================ helpers
def pick(df: pd.DataFrame, column: str, selected) -> pd.DataFrame:
    """Slicer logic: an empty selection means 'All'."""
    if selected is None or len(selected) == 0:
        return df
    return df[df[column].isin(selected)]


def money(value: float) -> str:
    return f"R$ {value:,.0f}"


def chart(fig, height: int = 340):
    fig.update_layout(
        height=height,
        margin=dict(l=10, r=10, t=50, b=10),
        paper_bgcolor="rgba(0,0,0,0)",
        plot_bgcolor="rgba(0,0,0,0)",
        title_x=0.02,
        legend_title_text="",
    )
    st.plotly_chart(fig)


def hbar(df, x, y, title):
    fig = px.bar(df, x=x, y=y, orientation="h", title=title, color_discrete_sequence=COLORS)
    fig.update_layout(yaxis={"categoryorder": "total ascending"})
    chart(fig)


def vbar(df, x, y, title, color=None):
    fig = px.bar(df, x=x, y=y, title=title, color=color, color_discrete_sequence=COLORS)
    chart(fig)


def line(df, x, y, title):
    fig = px.line(df, x=x, y=y, markers=True, title=title, color_discrete_sequence=COLORS)
    chart(fig)


def header(title: str, idx: int):
    """Banner, page title, and the prev/next arrows the report uses."""
    cols = st.columns([2.2, 6, 0.5, 0.5])
    with cols[0]:
        if BANNER.exists():
            st.image(str(BANNER))
    with cols[1]:
        st.markdown(
            f"<h1 style='text-align:center; margin-top:0.6rem;'>{title}</h1>",
            unsafe_allow_html=True,
        )
    if idx > 0:
        with cols[2]:
            st.button("◀", key=f"prev_{idx}", on_click=go_to, args=(idx - 1,))
    if idx < len(PAGES) - 1:
        with cols[3]:
            st.button("▶", key=f"next_{idx}", on_click=go_to, args=(idx + 1,))


def go_to(idx: int):
    st.session_state["page_idx"] = idx


# Slicer widgets (an empty selection means All, like Power BI's default list slicer)
def slicer_multi(key: str, label: str, options: list, page: str):
    return st.multiselect(label, options, default=[], key=f"{page}-{key}", placeholder="All")


def slicer_range(key: str, label: str, lo, hi, page: str):
    return st.slider(label, min_value=lo, max_value=hi, value=(lo, hi), key=f"{page}-{key}")


def slicer_text(key: str, label: str, page: str):
    return st.text_input(label, key=f"{page}-{key}", placeholder="contains...")


# ============================================================ filtering
def build_frames(d: dict, sel: dict) -> dict:
    """Apply the page's slicer selections to each table, following the report's relationships."""
    o = d["orders"]
    o = pick(o, "year", sel.get("year"))
    o = pick(o, "customer_state", sel.get("state"))
    o = pick(o, "customer_city", sel.get("city"))
    o = pick(o, "order_status", sel.get("status"))
    if sel.get("zip"):
        o = o[o["customer_zip_code_prefix"].astype(str).str.contains(sel["zip"], na=False)]
    ids = o["order_id"]

    items = d["items"][d["items"]["order_id"].isin(ids)]
    items = pick(items, "category", sel.get("category"))
    items = pick(items, "seller_state", sel.get("seller_state"))

    pay = d["payments"][d["payments"]["order_id"].isin(ids)]
    pay = pick(pay, "payment_type", sel.get("payment_type"))
    if sel.get("installments"):
        lo, hi = sel["installments"]
        pay = pay[pay["payment_installments"].between(lo, hi)]

    rev = d["reviews"][d["reviews"]["order_id"].isin(ids)]
    rev = pick(rev, "review_year", sel.get("review_year"))
    if sel.get("score"):
        lo, hi = sel["score"]
        rev = rev[rev["review_score"].between(lo, hi)]

    return {"orders": o, "items": items, "payments": pay, "reviews": rev}


def options(d: dict) -> dict:
    o, items = d["orders"], d["items"]
    return {
        "years": sorted(o["year"].dropna().astype(int).unique().tolist()),
        "states": sorted(o["customer_state"].dropna().unique().tolist()),
        "cities": sorted(o["customer_city"].dropna().unique().tolist()),
        "statuses": sorted(o["order_status"].dropna().unique().tolist()),
        "categories": sorted(items["category"].dropna().unique().tolist()),
        "seller_states": sorted(items["seller_state"].dropna().unique().tolist()),
        "payment_types": sorted(d["payments"]["payment_type"].dropna().unique().tolist()),
        "review_years": sorted(d["reviews"]["review_year"].dropna().astype(int).unique().tolist()),
        "inst_min": int(d["payments"]["payment_installments"].min()),
        "inst_max": int(d["payments"]["payment_installments"].max()),
    }


# ============================================================ pages
def page_orders(d, opt):
    key = "orders"
    left, right = st.columns([1, 5])
    with left:
        sel = {
            "year": slicer_multi("year", "Year", opt["years"], key),
            "state": slicer_multi("state", "customer_state", opt["states"], key),
            "status": slicer_multi("status", "order_status", opt["statuses"], key),
            "category": slicer_multi("category", "product_category_name", sorted(opt["categories"]), key),
        }
    f = build_frames(d, sel)
    items = f["items"]
    o_items = f["orders"][f["orders"]["order_id"].isin(items["order_id"])]
    pay = f["payments"][f["payments"]["order_id"].isin(o_items["order_id"])]

    total_orders = items["order_id"].nunique()
    item_sales = items["price"].sum()
    aov = pay["payment_value"].sum() / total_orders if total_orders else 0
    delivery_rate = o_items["is_delivered"].mean() * 100 if len(o_items) else 0

    with right:
        cols = st.columns(4)
        cols[0].metric("Total Orders", f"{total_orders:,}")
        cols[1].metric("Total Item Sales", money(item_sales))
        cols[2].metric("Average Order Value", money(aov))
        cols[3].metric("Delivery Rate %", f"{delivery_rate:.2f}%")

        col1, col2 = st.columns(2)
        with col1:
            top_states = (
                o_items.groupby("customer_state")["order_id"].nunique().nlargest(10)
                .rename("Total Orders").reset_index()
            )
            hbar(top_states, "Total Orders", "customer_state", "Total Orders by customer_state (Top 10)")
        with col2:
            status = (
                o_items.groupby("order_status")["order_id"].nunique()
                .rename("Total Orders").reset_index()
            )
            hbar(status, "Total Orders", "order_status", "Total Orders by order_status")

        col3, col4 = st.columns(2)
        with col3:
            by_year = items.groupby("year")["price"].sum().reset_index()
            by_year["year"] = by_year["year"].astype(int).astype(str)
            line(by_year, "year", "price", "Total Item Sales by Year")
        with col4:
            top_cat = (
                items.groupby("category")["price"].sum().nlargest(10).rename("Total Item Sales").reset_index()
            )
            vbar(top_cat, "category", "Total Item Sales", "Total Item Sales by product_category_name (Top 10)")


def page_reviews(d, opt):
    key = "reviews"
    left, right = st.columns([1, 5])
    with left:
        sel = {
            "review_year": slicer_multi("review_year", "Year", opt["review_years"], key),
            "score": slicer_range("score", "review_score", 1, 5, key),
            "state": slicer_multi("state", "customer_state", opt["states"], key),
            "status": slicer_multi("status", "order_status", opt["statuses"], key),
        }
    f = build_frames(d, sel)
    rev = f["reviews"]
    o = f["orders"]
    rev_o = rev.merge(o[["order_id", "customer_state"]], on="order_id", how="left")

    with right:
        cols = st.columns(4)
        cols[0].metric("Average Review Score", f"{rev['review_score'].mean():.2f}" if len(rev) else "0.00")
        cols[1].metric("Five Star Reviews", f"{int((rev['review_score'] == 5).sum()):,}")
        cols[2].metric("Low Score Reviews", f"{int((rev['review_score'] <= 2).sum()):,}")
        cols[3].metric("Review Count", f"{len(rev):,}")

        col1, col2 = st.columns(2)
        with col1:
            combo = pd.DataFrame({
                "measure": ["Sum of review_score", "Review Count"],
                "value": [rev["review_score"].sum(), len(rev)],
            })
            vbar(combo, "measure", "value", "Sum of review_score and Review Count", color="measure")
        with col2:
            by_state = (
                rev_o.groupby("customer_state").size().nlargest(10).rename("Review Count").reset_index()
            )
            hbar(by_state, "Review Count", "customer_state", "Review Count by customer_state (Top 10)")

        col3, col4 = st.columns(2)
        with col3:
            avg_year = rev.groupby("review_year")["review_score"].mean().reset_index()
            avg_year["review_year"] = avg_year["review_year"].astype(int).astype(str)
            line(avg_year, "review_year", "review_score", "Average Review Score by Year")
        with col4:
            dist = rev["review_score"].value_counts().reindex([1, 2, 3, 4, 5], fill_value=0)
            dist = dist.rename_axis("review_score").reset_index(name="Review Count")
            dist["review_score"] = dist["review_score"].astype(str)
            vbar(dist, "review_score", "Review Count", "Review Count by review_score")


def page_customers(d, opt):
    key = "customers"
    left, right = st.columns([1, 5])
    with left:
        sel = {
            "year": slicer_multi("year", "Year", opt["years"], key),
            "state": slicer_multi("state", "customer_state", opt["states"], key),
            "city": slicer_multi("city", "customer_city", opt["cities"], key),
            "zip": slicer_text("zip", "customer_zip_code_prefix", key),
        }
    f = build_frames(d, sel)
    o = f["orders"]
    pay = f["payments"]

    customers_total = o["customer_unique_id"].nunique()
    per_customer = o.groupby("customer_unique_id")["order_id"].nunique()
    repeat_customers = int((per_customer > 1).sum())
    repeat_rate = repeat_customers / customers_total * 100 if customers_total else 0
    orders_per_customer = o["order_id"].nunique() / customers_total if customers_total else 0

    with right:
        cols = st.columns(4)
        cols[0].metric("Total Customers", f"{customers_total:,}")
        cols[1].metric("Repeat Customers", f"{repeat_customers:,}")
        cols[2].metric("Repeat Customer Rate %", f"{repeat_rate:.2f}%")
        cols[3].metric("Orders per Customer", f"{orders_per_customer:.2f}")

        col1, col2 = st.columns(2)
        with col1:
            cust_pay = (
                pay.merge(o[["order_id", "customer_id"]], on="order_id")
                .groupby("customer_id")["payment_value"].sum().nlargest(10)
                .rename("Total Payment Value").reset_index()
            )
            hbar(cust_pay, "Total Payment Value", "customer_id",
                 "Total Payment Value by customer_id (Top 10)")
        with col2:
            by_city = (
                o.groupby("customer_city")["customer_unique_id"].nunique()
                .sort_values(ascending=False).head(25)
                .rename("Total Customers").reset_index()
            )
            hbar(by_city, "Total Customers", "customer_city", "Total Customers by customer_city (Top 25)")

        col3, col4 = st.columns(2)
        with col3:
            by_year = o.groupby("year")["customer_unique_id"].nunique().reset_index()
            by_year["year"] = by_year["year"].astype(int).astype(str)
            line(by_year, "year", "customer_unique_id", "Total Customers by Year")
        with col4:
            combo = pd.DataFrame({
                "measure": ["Repeat Customers", "Total Customers"],
                "value": [repeat_customers, customers_total],
            })
            vbar(combo, "measure", "value", "Repeat Customers and Total Customers", color="measure")


def page_payments(d, opt):
    key = "payments"
    left, right = st.columns([1, 5])
    with left:
        sel = {
            "year": slicer_multi("year", "Year", opt["years"], key),
            "payment_type": slicer_multi("payment_type", "payment_type", opt["payment_types"], key),
            "status": slicer_multi("status", "order_status", opt["statuses"], key),
            "installments": slicer_range("inst", "payment_installments",
                                         opt["inst_min"], opt["inst_max"], key),
        }
    f = build_frames(d, sel)
    pay = f["payments"].merge(f["orders"][["order_id", "del_year"]], on="order_id", how="left")

    with right:
        cols = st.columns(4)
        cols[0].metric("Total Payment Value", money(pay["payment_value"].sum()))
        cols[1].metric("Payment Records", f"{len(pay):,}")
        cols[2].metric("Average Payment Record Value", money(pay["payment_value"].mean() if len(pay) else 0))
        cols[3].metric("Average Installments", f"{pay['payment_installments'].mean():.2f}" if len(pay) else "0.00")

        col1, col2 = st.columns(2)
        with col1:
            by_type = pay.groupby("payment_type")["payment_value"].sum().reset_index()
            fig = px.pie(by_type, names="payment_type", values="payment_value", hole=0.5,
                         title="Total Payment Value by payment_type", color_discrete_sequence=COLORS)
            chart(fig)
        with col2:
            seq = pay.groupby("payment_type")["payment_sequential"].sum().reset_index()
            fig = px.pie(seq, names="payment_type", values="payment_sequential",
                         title="Sum of payment_sequential by payment_type", color_discrete_sequence=COLORS)
            chart(fig)

        col3, col4 = st.columns(2)
        with col3:
            by_del = pay.dropna(subset=["del_year"]).groupby("del_year")["payment_value"].sum().reset_index()
            by_del["del_year"] = by_del["del_year"].astype(int).astype(str)
            line(by_del, "del_year", "payment_value", "Total Payment Value by del_year")
        with col4:
            records = pay.groupby("payment_type").size().rename("Payment Records").reset_index()
            hbar(records, "Payment Records", "payment_type", "Payment Records by payment_type")


def page_sellers(d, opt):
    key = "sellers"
    left, right = st.columns([1, 5])
    with left:
        sel = {
            "year": slicer_multi("year", "Year", opt["years"], key),
            "seller_state": slicer_multi("seller_state", "seller_state", opt["seller_states"], key),
            "category": slicer_multi("category", "product_category_name", sorted(opt["categories"]), key),
            "status": slicer_multi("status", "order_status", opt["statuses"], key),
        }
    f = build_frames(d, sel)
    items = f["items"]

    with right:
        cols = st.columns(4)
        cols[0].metric("Total Sellers", f"{items['seller_id'].nunique():,}")
        cols[1].metric("Total Orders", f"{items['order_id'].nunique():,}")
        cols[2].metric("Total Items Sold", f"{len(items):,}")
        cols[3].metric("Freight per Item", money(items["freight_value"].mean() if len(items) else 0))

        col1, col2 = st.columns(2)
        with col1:
            top_sellers = (
                items.groupby("seller_id").size().nlargest(10).rename("Total Items Sold").reset_index()
            )
            hbar(top_sellers, "Total Items Sold", "seller_id", "Total Items Sold by seller_id (Top 10)")
        with col2:
            top_cat = (
                items.groupby("category").size().nlargest(10).rename("Total Items Sold").reset_index()
            )
            hbar(top_cat, "Total Items Sold", "category", "Total Items Sold by product_category_name (Top 10)")

        col3, col4 = st.columns(2)
        with col3:
            by_state = (
                items.groupby("seller_state")["seller_id"].nunique().nlargest(10)
                .rename("Total Sellers").reset_index()
            )
            hbar(by_state, "Total Sellers", "seller_state", "Total Sellers by seller_state (Top 10)")
        with col4:
            by_state_items = (
                items.groupby("seller_state").size().nlargest(10)
                .rename("Total Items Sold").reset_index()
            )
            hbar(by_state_items, "Total Items Sold", "seller_state",
                 "Total Items Sold by seller_state (Top 10)")


PAGE_FUNCTIONS = [page_orders, page_reviews, page_customers, page_payments, page_sellers]


# ============================================================ main
def main():
    if "page_idx" not in st.session_state:
        st.session_state["page_idx"] = 0
    idx = st.session_state["page_idx"]

    d = load_data()
    opt = options(d)

    header(PAGES[idx], idx)
    PAGE_FUNCTIONS[idx](d, opt)


# ============================================================ late delivery prediction
def prediction_page():
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


# ============================================================ login


def get_secret(name: str, default: str) -> str:
    """Read a value from Streamlit secrets, falling back to the default if none is configured."""
    try:
        return st.secrets[name]
    except Exception:
        return default


APP_USERNAME = get_secret("APP_USERNAME", "olist")
APP_PASSWORD = get_secret("APP_PASSWORD", "pass123")


def check_login(username: str, password: str) -> bool:
    user_ok = hmac.compare_digest(username.encode("utf-8"), APP_USERNAME.encode("utf-8"))
    pass_ok = hmac.compare_digest(password.encode("utf-8"), APP_PASSWORD.encode("utf-8"))
    return user_ok and pass_ok


def login_page():
    st.title("Olist Analytics Login")
    with st.form("login_form"):
        username = st.text_input("Username")
        password = st.text_input("Password", type="password")
        submitted = st.form_submit_button("Log in")
    if submitted:
        if check_login(username, password):
            st.session_state["authenticated"] = True
            st.rerun()
        else:
            st.error("Invalid username or password.")


def run_app():
    if not st.session_state.get("authenticated", False):
        login_page()
        return

    st.sidebar.title("Olist Analytics")
    app_choice = st.sidebar.radio(
        "Application", ["Sales Dashboard", "Late Delivery Prediction"]
    )
    st.sidebar.write(f"Signed in as **{APP_USERNAME}**")
    if st.sidebar.button("Log out"):
        st.session_state["authenticated"] = False
        st.rerun()

    if app_choice == "Sales Dashboard":
        main()
    else:
        prediction_page()


run_app()

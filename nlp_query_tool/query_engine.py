"""
query_engine.py

Translates a plain-English business question into a read-only SQL query
against the Olist database, executes it, and returns a natural-language
answer alongside the underlying SQL (for transparency and trust).

This module has no UI dependency — app.py (Streamlit) imports it, but it
could equally be called from a CLI or a notebook.
"""

import os
import re
import pandas as pd
from openai import OpenAI
from sqlalchemy import create_engine, text

# --------------------------------------------------------------------------
# Schema description given to the model. Keeping this explicit (rather than
# introspecting the live DB) means the model only ever sees the tables we
# want it querying, and the prompt stays stable and auditable.
# --------------------------------------------------------------------------
SCHEMA_DESCRIPTION = """
You have access to a read-only PostgreSQL database with the following
tables and views:

TABLE orders(order_id, customer_id, order_status, order_purchase_timestamp,
             order_approved_at, order_delivered_carrier_date,
             order_delivered_customer_date, order_estimated_delivery_date)

TABLE customers(customer_id, customer_unique_id, customer_zip_code_prefix,
                 customer_city, customer_state)

TABLE order_items(order_id, order_item_id, product_id, seller_id,
                   shipping_limit_date, price, freight_value)

TABLE order_payments(order_id, payment_sequential, payment_type,
                      payment_installments, payment_value)

TABLE products(product_id, product_category_name, product_weight_g, ...)

VIEW category_profitability(category, items_sold, total_revenue,
    total_freight_cost, total_margin_proxy, avg_margin_pct,
    margin_rank, revenue_rank)
    -- One row per product category. margin_proxy = price - freight_value.
    -- This is the primary table for profitability/margin questions.

Note: there is no "profit" or "cost of goods" column anywhere in this
database. If asked about "profit", answer using margin_proxy /
avg_margin_pct and say explicitly that this is a shipping-cost-adjusted
margin proxy, not true profit.
"""

SQL_SYSTEM_PROMPT = f"""You are a SQL generator for a PostgreSQL database.
{SCHEMA_DESCRIPTION}

Rules:
- Output ONLY a single SQL SELECT query. No explanation, no markdown
  fences, no semicolon-separated multiple statements.
- NEVER generate INSERT, UPDATE, DELETE, DROP, ALTER, TRUNCATE, or any
  statement that modifies data or schema.
- Only reference the tables/views listed above.
- If the question cannot be answered with these tables, output exactly:
  NO_QUERY: <short reason>
"""

ANSWER_SYSTEM_PROMPT = """You are a data analyst summarizing SQL query
results for a business stakeholder. Given the original question, the SQL
that was run, and the resulting data, write a concise (2-4 sentence)
plain-English answer. Include the specific numbers. If the data is empty,
say so plainly rather than guessing.
"""

# Basic guardrail: reject anything that isn't a single, clean SELECT.
FORBIDDEN_KEYWORDS = re.compile(
    r"\b(INSERT|UPDATE|DELETE|DROP|ALTER|TRUNCATE|GRANT|REVOKE|CREATE)\b",
    re.IGNORECASE,
)


class QueryEngineError(Exception):
    pass


def get_engine(pg_password: str):
    """Build a SQLAlchemy engine for the local olist_analysis database."""
    return create_engine(
        f"postgresql+psycopg2://postgres:{pg_password}@localhost:5432/olist_analysis"
    )


def _get_client() -> OpenAI:
    """
    Returns an OpenAI-SDK-compatible client. Defaults to Groq's free API
    (no credit card required to sign up) but works with OpenAI too if you
    set LLM_PROVIDER=openai.
    """
    provider = os.environ.get("LLM_PROVIDER", "groq").lower()

    if provider == "groq":
        api_key = os.environ.get("GROQ_API_KEY")
        if not api_key:
            raise QueryEngineError(
                "GROQ_API_KEY environment variable is not set. "
                "Get a free key (no card required) from console.groq.com/keys."
            )
        return OpenAI(api_key=api_key, base_url="https://api.groq.com/openai/v1")

    # provider == "openai"
    api_key = os.environ.get("OPENAI_API_KEY")
    if not api_key:
        raise QueryEngineError(
            "OPENAI_API_KEY environment variable is not set. "
            "Get a key from platform.openai.com/api-keys and set it before running."
        )
    return OpenAI(api_key=api_key)


def _get_model_name() -> str:
    provider = os.environ.get("LLM_PROVIDER", "groq").lower()
    return "llama-3.3-70b-versatile" if provider == "groq" else "gpt-4o-mini"


def question_to_sql(client: OpenAI, question: str) -> str:
    """Ask the LLM to translate a plain-English question into SQL."""
    response = client.chat.completions.create(
        model=_get_model_name(),
        max_tokens=400,
        messages=[
            {"role": "system", "content": SQL_SYSTEM_PROMPT},
            {"role": "user", "content": question},
        ],
    )
    sql = response.choices[0].message.content.strip()

    # Strip accidental markdown fences, just in case
    sql = re.sub(r"^```sql\s*|\s*```$", "", sql, flags=re.IGNORECASE).strip()

    if sql.startswith("NO_QUERY"):
        raise QueryEngineError(sql.replace("NO_QUERY:", "").strip())

    if FORBIDDEN_KEYWORDS.search(sql):
        raise QueryEngineError(
            "Generated query contained a disallowed keyword and was blocked "
            "for safety. Try rephrasing your question."
        )

    if not sql.upper().startswith("SELECT"):
        raise QueryEngineError(
            "Generated output wasn't a SELECT query. Try rephrasing your question."
        )

    return sql


def run_query(engine, sql: str) -> pd.DataFrame:
    """Execute the generated SQL and return a DataFrame."""
    with engine.connect() as conn:
        result = conn.execute(text(sql))
        rows = result.fetchall()
        columns = result.keys()
    return pd.DataFrame(rows, columns=columns)


def summarize_result(client: OpenAI, question: str, sql: str, df: pd.DataFrame) -> str:
    """Ask the LLM to turn the raw query result into a plain-English answer."""
    data_preview = df.head(20).to_string(index=False) if not df.empty else "(no rows returned)"

    user_content = (
        f"Question: {question}\n\n"
        f"SQL run:\n{sql}\n\n"
        f"Result:\n{data_preview}"
    )
    response = client.chat.completions.create(
        model=_get_model_name(),
        max_tokens=300,
        messages=[
            {"role": "system", "content": ANSWER_SYSTEM_PROMPT},
            {"role": "user", "content": user_content},
        ],
    )
    return response.choices[0].message.content.strip()


def ask(question: str, pg_password: str) -> dict:
    """
    Full pipeline: question -> SQL -> execute -> plain-English answer.
    Returns a dict with keys: sql, dataframe, answer.
    Raises QueryEngineError with a user-facing message on failure.
    """
    client = _get_client()
    engine = get_engine(pg_password)

    sql = question_to_sql(client, question)

    try:
        df = run_query(engine, sql)
    except Exception as e:
        raise QueryEngineError(f"The generated query failed to run: {e}\n\nSQL:\n{sql}")

    answer = summarize_result(client, question, sql, df)

    return {"sql": sql, "dataframe": df, "answer": answer}
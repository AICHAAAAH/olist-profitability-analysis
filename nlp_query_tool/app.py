"""
app.py

Streamlit interface for the Olist NLP query tool.

Run with:
    streamlit run nlp_query_tool/app.py

Requires the ANTHROPIC_API_KEY environment variable to be set, and a local
PostgreSQL 'olist_analysis' database already loaded (see sql/ scripts).
"""

import streamlit as st
from query_engine import ask, QueryEngineError

st.set_page_config(page_title="Olist Data Assistant", page_icon="📊", layout="centered")

st.title("📊 Olist Data Assistant")
st.caption(
    "Ask a plain-English question about category profitability, revenue, "
    "or margins. The question is translated into SQL, run against the "
    "real database, and answered with the actual numbers."
)

with st.expander("Example questions"):
    st.markdown(
        "- What is the average margin percentage for the telephony category?\n"
        "- Which 5 categories have the highest revenue?\n"
        "- How does the housewares category's margin compare to health_beauty?\n"
        "- What is the total revenue across all categories?"
    )

pg_password = st.text_input("PostgreSQL password", type="password")
question = st.text_area("Your question", placeholder="e.g. What's the margin percentage for telephony?")

if st.button("Ask", type="primary", disabled=not (pg_password and question)):
    with st.spinner("Translating question to SQL and querying the database..."):
        try:
            result = ask(question, pg_password)

            st.subheader("Answer")
            st.write(result["answer"])

            with st.expander("Show SQL used"):
                st.code(result["sql"], language="sql")

            if not result["dataframe"].empty:
                with st.expander("Show raw result data"):
                    st.dataframe(result["dataframe"])

        except QueryEngineError as e:
            st.error(str(e))
        except Exception as e:
            st.error(f"Unexpected error: {e}")

st.divider()
st.caption(
    "Note: this tool only ever generates SELECT queries and blocks any "
    "attempt at data modification. Margin figures are a shipping-cost "
    "proxy, not true profit — see the project README for methodology."
)
import sqlalchemy.exc
from sqlalchemy.engine import URL, create_engine
from azure.identity import DefaultAzureCredential
import struct
import pandas as pd

# connection parameters
server = 'tcp:ods-sql-server-us.database.windows.net'
database = 'salesops-sql-prod-us'
conn_str = (f'DRIVER=ODBC Driver 17 for SQL Server;'
            f'SERVER={server};'
            f'DATABASE={database};'
            f'ENCRYPT=yes;'
            f'TRUSTSERVERCERTIFICATE=no;'
            f'connection timeout=30')
credential = DefaultAzureCredential(exclude_interactive_browser_credential=False)
token = credential.get_token("https://database.windows.net/.default").token.encode("UTF-16-LE")
token_struct = struct.pack(f'<I{len(token)}s', len(token), token)
connection_url = URL.create("mssql+pyodbc",
                            query={"odbc_connect": conn_str})
engine = create_engine(connection_url,
                       connect_args={"attrs_before": {1256: token_struct}})

# read sql queries
with open('./data sources/data.sql') as sql_file:
    sql = sql_file.read()
with open('./data sources/slide 10.sql') as slide_10:
    slide_10_sql = slide_10.read()
with open('./data sources/national_perspective.sql') as slide_11:
    slide_11_sql = slide_11.read()
with open('./data sources/patient_access.sql') as pat_access:
    pat_access_sql = pat_access.read()
with open ('./data sources/setup_sql.sql') as setup:
    setup_sql = setup.read()
with engine.connect() as conn:
    df = pd.read_sql(sql, conn)
    df["ACCOUNT_NAME"] = df["ACCOUNT_NAME"].str.title()
    slide_10_df = pd.read_sql(slide_10_sql, conn)
    slide_11_df = pd.read_sql(slide_11_sql, conn)
    conn.exec_driver_sql(setup_sql)
    pat_access_df = pd.read_sql(pat_access_sql, conn)

df["CMS_ID"] = df["CMS_ID"].astype("string").str.strip()

# read Excel files
apc1580 = pd.read_excel("./data sources/CY2026_APC_Rates_1.26.2026.xlsx",
                        header=10,
                        usecols=[0, 6])
apc1580.rename(columns={apc1580.columns[0]: "CMS_ID"}, inplace=True)
apc1580["CMS_ID"] = apc1580["CMS_ID"].astype("string").str.strip()

msdrg276 = pd.read_excel("./data sources/IPPS payment rates by provider, for emailing, 011526.xlsx",
                         header=12,
                         usecols=[0, 10])
msdrg276.rename(columns={msdrg276.columns[0]: "CMS_ID"}, inplace=True)
msdrg276["CMS_ID"] = msdrg276["CMS_ID"].astype("string").str.strip()

# join
df = df.merge(right=apc1580, on="CMS_ID", how="left")
df = df.merge(right=msdrg276, on="CMS_ID", how="left")

# df.to_excel("./test.xlsx", index=False)



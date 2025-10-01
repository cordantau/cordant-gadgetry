# fetch-metadata.py

Fetches metadata from the **Google Play Store** and saves it to an Excel file.

Ensure the following are installed `pip install -r requirements.txt`

```bash title="requirements.txt"
beautifulsoup4
lxml
openpyxl
pandas
requests
xlsxwriter
```

Create a new .xlsx file and in column A list the apps (name or ID) you want metadata for, e.g.,

| A                          |
| -------------------------- |
| 13 Cabs                    |
| com.google.android.youtube |

Run the python script with your file

```python
--8<-- "scripts/python/fetch-metadata.py"
```

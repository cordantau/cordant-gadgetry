import datetime
import json
import sys
import pandas as pd
import requests
from bs4 import BeautifulSoup

"""
Fetches metadata from the Google Play Store and saves it to an Excel file.

Usage: python fetch-metadata.py <filename> [<num_rows>]

Parameters:
    filename (str): The name of the Excel file to load and process.
    num_rows (int, optional): The number of rows to process. If not provided, all rows will be processed.

Returns:
    tuple: A tuple containing the following metadata:
        - application_id (str): The application ID of the app.
        - friendly_name (str): The friendly name of the app.
        - description (str): The description of the app.
        - category (str): The category of the app.
        - content_rating (str): The content rating of the app.
        - application_rating (float or str): The rating of the app.
        - pricing (str): The pricing information of the app.
"""


# Function to scrape data from Google Play Store page
def scrape_google_play(app_name):
    """
    Scrapes metadata from the Google Play Store for a given app.

    Args:
        app_name (str): The name or application ID of the app to scrape.

    Returns:
        tuple: A tuple containing the metadata (see above for details).:
    """
    # Check if app_name starts with 'com.android' and is exactly 'com.android.chrome'
    if app_name.startswith("com.android") and app_name != "com.android.chrome":
        print(f"Skipping {app_name}")
        return ("Not applicable",) * 7

    # If the app_name does not contain '.'
    if "." not in app_name:
        # Perform a search query if the app_name is a general term without a dot
        search_url = f"https://play.google.com/store/search?q={app_name}&c=apps"
        try:
            search_response = requests.get(search_url)
            if search_response.status_code == 200:
                search_soup = BeautifulSoup(search_response.content, "lxml")
                # Find the first section that might contain the needed <a> tag
                section = search_soup.find("section")
                if section:
                    # Within the found section, find the first href containing '/store/apps/details?id='
                    link = section.find(
                        "a",
                        href=True,
                        attrs={
                            "href": lambda href: href
                            and "/store/apps/details?id=" in href
                        },
                    )
                    if link:
                        app_name = link["href"].split("=")[
                            1
                        ]  # Extract the new app_name (application ID)
                    else:
                        print(f"No valid app found for search term: {app_name}")
                        return ("Not found",) * 7
        except Exception as e:
            print(f"Failed to fetch search results for {app_name}: {str(e)}")
            return ("Not found",) * 7

    # Fetch data from the Google Play Store page
    url = f"https://play.google.com/store/apps/details?id={app_name}&hl=en"
    try:
        response = requests.get(url)
        if response.status_code == 200:
            soup = BeautifulSoup(response.content, "lxml")
            # Find the script tag with type 'application/ld+json'
            script_tag = soup.find("script", {"type": "application/ld+json"})
            if script_tag:
                # Parse JSON content from script_tag
                data = json.loads(script_tag.string)
                # Extract the required values
                application_id = app_name
                friendly_name = data.get("name", "Not Found")
                description = data.get("description", "Not Found")
                category = data.get("applicationCategory", "Not Found")
                content_rating = data.get("contentRating", "Not Found")
                aggregate_rating = data.get("aggregateRating", {})
                application_rating = (
                    round(float(aggregate_rating.get("ratingValue")), 2)
                    if aggregate_rating
                    else "Not Found"
                )
                offers = data.get("offers", [])
                pricing = offers[0].get("price", "Not Found") if offers else "Not Found"

            print(f"Data fetched for {app_name} successfully.")

            return (
                application_id,
                friendly_name,
                description,
                category,
                content_rating,
                application_rating,
                pricing,
            )
        else:
            print(
                f"Failed to fetch data for {app_name} - Status code: {response.status_code}"
            )
            return ("Not found",) * 7
    except Exception as e:
        print(f"Error fetching data for {app_name} - {str(e)}")
        return ("Not found",) * 7


def load_and_process_excel(filename, num_rows=None):
    """
    Load and process an Excel file containing application names.

    Args:
        filename (str): The path to the Excel file.
        num_rows (int, optional): The number of rows to read from the Excel file. Defaults to None, which reads all rows.

    Returns:
        pandas.DataFrame: A DataFrame containing the processed data with additional columns populated.
    """
    df = pd.read_excel(filename, header=None)
    if num_rows is not None:
        df = df.head(num_rows)

    df.columns = ["Application Name"]

    df_unique = df.drop_duplicates(subset=["Application Name"]).copy()

    # Initialise additional columns
    df_unique["Application ID"] = ""
    df_unique["Friendly Name"] = ""
    df_unique["Description"] = ""
    df_unique["Category"] = ""
    df_unique["Content Rating"] = ""
    df_unique["Application Rating"] = ""
    df_unique["Pricing"] = ""

    # Fetch data and populate columns
    for index, row in df_unique.iterrows():
        (
            application_id,
            friendly_name,
            description,
            category,
            content_rating,
            application_rating,
            pricing,
        ) = scrape_google_play(row["Application Name"])

        df_unique.loc[index, "Application ID"] = application_id
        df_unique.loc[index, "Friendly Name"] = friendly_name
        df_unique.loc[index, "Description"] = description
        df_unique.loc[index, "Category"] = category
        df_unique.loc[index, "Content Rating"] = content_rating
        df_unique.loc[index, "Application Rating"] = application_rating
        df_unique.loc[index, "Pricing"] = pricing

    return df_unique


def main():
    # Check minimum requirement for filename
    if len(sys.argv) < 2:
        print("Usage: python fetch-metadata.py <filename> [<num_rows>]")
        sys.exit(1)

    filename = sys.argv[1]
    num_rows = (
        int(sys.argv[2]) if len(sys.argv) > 2 else None
    )  # Number of rows to process
    result_df = load_and_process_excel(filename, num_rows)

    # Get today's as 'yyyymmdd' and save the output to an Excel file
    today = datetime.datetime.now().strftime("%Y%m%d")
    output_filename = f"apps_metadata_output_{today}.xlsx"
    result_df.to_excel(output_filename, index=False)

    print(f"Processing complete. Data saved to '{output_filename}'.")


if __name__ == "__main__":
    main()

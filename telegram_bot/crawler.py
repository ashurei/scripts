import requests
from bs4 import BeautifulSoup
from tabulate import tabulate
from config import LOGIN_DATA, LOGIN_URL, INDEX_URL, LIST_URL

### All of loan books
def list_all():
    result = []
    for account in LOGIN_DATA:
        login_data = {
                "userId": account[0],
                "password": account[1]
                }
        session = requests.Session()

        # Send login post request
        response = session.post(LOGIN_URL, data=login_data)

        page = session.get(INDEX_URL)
        soup = BeautifulSoup(page.text, "html.parser")

        list_info = []
        name = soup.select_one('div.centerItem > p strong').text.strip()
        list_info.append(name)

        for a_tag in soup.select('div.centerItem > div > a'):
            #label = a_tag.contents[0].strip()
            value = a_tag.find('span').text.strip()
            list_info.append(value)

        result.append(list_info)

    #print(result)
    return result

### Personal loan books
def list_for_user(user):
    result = []

    match user:
        case "jaehyun":
            login_data = {
                    "userId": LOGIN_DATA[0][0],
                    "password": LOGIN_DATA[0][1]
                    }
        case "jihye":
            login_data = {
                    "userId": LOGIN_DATA[1][0],
                    "password": LOGIN_DATA[1][1]
                    }
        case "seungah":
            login_data = {
                    "userId": LOGIN_DATA[2][0],
                    "password": LOGIN_DATA[2][1]
                    }
        case "seungwoo":
            login_data = {
                    "userId": LOGIN_DATA[3][0],
                    "password": LOGIN_DATA[3][1]
                    }
        case default:
            return "Nothing"

    session = requests.Session()

    # Send login post request
    response = session.post(LOGIN_URL, data=login_data)

    page = session.get(LIST_URL)
    soup = BeautifulSoup(page.text, "html.parser")

    result = []
    for book in soup.select('div.myArticleWrap > div.myArticle-list'):
        title = book.select_one('div.title').text.strip()
        div_info = book.select('div.info')[1]
        span_data = div_info.select('span')[1].text.strip()

        #print("제목:", title)
        #print(span_data)
        result.append("제목 : " + title)
        result.append(span_data)

    #print(result)
    text = ""
    for res in result:
        text = text + res + "\n"

    escaped_text = escape_markdown(text)
    return escaped_text

### Remove escape text for markdown
def escape_markdown(text):
    escape_chars = r'_*[]()~`>#+-=|{}.!'
    for ch in escape_chars:
        text = text.replace(ch, f"\\{ch}")
    return text

#list_for_user("jaehyun")

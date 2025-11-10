### 2025.11.10 r13

import logging
from telegram import InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, filters, ConversationHandler, CallbackQueryHandler
import crawler as cw
from config import TELEGRAM_BOT_TOKEN

#logging.basicConfig(format='%(asctime)s - %(name)s - %(levelname)s - %(message)s', level=logging.DEBUG)
#logger = logging.getLogger(__name__)

STEP1, STEP2 = range(2)

### Command /start
async def start(update, context):
    #await update.message.reply_text("This is Ashurei's telegram bot.\n/crawl")
    chat_id = update.effective_chat.id
    reply_markup = InlineKeyboardMarkup([
        [InlineKeyboardButton("책대출 현황", callback_data="list_loan")]
       ,[InlineKeyboardButton("개별 책대출", callback_data="each_loan")]
    ])
    await context.bot.send_message(chat_id=chat_id, text="글마루도서관", reply_markup=reply_markup)
    return STEP1 #ConversationHandler.END

### STEP1
async def step1(update, context):
    query = update.callback_query
    await query.answer()
    # 책대출 현황
    if query.data == "list_loan":
        await list_loan(update, context)
        #return ConversationHandler.END
        return STEP1
    # 개별 책대출
    elif query.data == "each_loan":
        reply_markup = InlineKeyboardMarkup([
             [InlineKeyboardButton("안재현", callback_data="jaehyun")]
            ,[InlineKeyboardButton("유지혜", callback_data="jihye")]
            ,[InlineKeyboardButton("안승아", callback_data="seungah")]
            ,[InlineKeyboardButton("안승우", callback_data="seungwoo")]
            ,[InlineKeyboardButton("(처음으로)", callback_data="go_start")]
        ])
        await query.edit_message_text(text="사람 선택", reply_markup=reply_markup)
        return STEP2

### STEP2
async def step2(update, context):
    query = update.callback_query
    await query.answer()

    # 초기 화면으로
    if query.data == "go_start":
        return await start(update, context)

    await each_loan(update, context, query.data)
    return STEP2

### List of loan books
async def list_loan(update, context):
    chat_id = update.effective_chat.id
    result = cw.list_all()
    text = "이름     대출 예약 솔이 희망\n"
    for res in result:
        text = text + (res[0] + "      " + res[1] + "      " + res[2] + "      " + res[3] + "      " + res[4] + "\n")
    await context.bot.send_message(chat_id=chat_id, text=text, parse_mode="MarkdownV2")

### List of personal loan books
async def each_loan(update, context, user):
    chat_id = update.effective_chat.id

    text = cw.list_for_user(user)
    if not text.strip():
        text = "대출한 책 없음"

    await context.bot.send_message(chat_id=chat_id, text=text, parse_mode="MarkdownV2")


def main():
    application = Application.builder().token(TELEGRAM_BOT_TOKEN).build()
    # Command
    conv_handler = ConversationHandler (
            entry_points = [CommandHandler('start', start)],
            states = {
                STEP1: [CallbackQueryHandler(step1, pattern="^(list_loan|each_loan|go_start)$")],
                STEP2: [CallbackQueryHandler(step2)]
            },
            fallbacks = [CommandHandler('start', start)],
    )
    application.add_handler(conv_handler)
    application.run_polling()

if __name__ == '__main__':
    main()

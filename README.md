# tg-spam in the Wiren Board chats

This repository runs [umputun/tg-spam](https://github.com/umputun/tg-spam) in two Wiren Board
Telegram chats. It holds no tg-spam code: the image is an upstream release built with our
patch, and a bot is updated by "Pull and redeploy" in Portainer.

How the bots run, update and roll back: [deploy/wb-compat/README.md](deploy/wb-compat/README.md).

GitHub still lists this repository as a fork of umputun/tg-spam and offers that repository
as the base of a new pull request: pick `wirenboard/tg-spam` instead.

tg-spam is by Umputun, under the MIT license in [LICENSE](LICENSE).

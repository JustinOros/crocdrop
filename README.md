# CrocDrop

Send big files from one computer to another. Nothing to install.

CrocDrop is a simple web front-end for [croc](https://github.com/schollz/croc). The site makes a code and gives you one command to paste. The command downloads croc into a temporary folder, runs the transfer, and offers to clean up when it is done.

Live site: https://justinoros.github.io/crocdrop/

## How to use it

**Receiving**

1. Open the site and click Receive.
2. Copy the link and send it to your friend.
3. Copy the command, paste it into Terminal (Mac, Linux) or PowerShell (Windows), and press Enter.
4. Files are saved to the folder you ran the command from. If you ran it from your home folder, they go to `Downloads/CrocDrop`.

**Sending**

1. Open the link your friend sent you (or click Send and paste their link or code).
2. Copy the command, paste it into Terminal or PowerShell, and press Enter.
3. Drag your files or folder into the window and press Enter. Pressing Enter on its own opens a folder picker.

## Good to know

- Works on Mac, Windows and Linux.
- Transfers are end-to-end encrypted by croc, and each file is hash checked when it finishes.
- If a transfer drops, the script keeps retrying. You can also run the same command again to resume.
- Keep both windows open until you see All done.
- The script blocks sleep while it runs.
- croc is pinned to v11.5.5 and checked against a SHA256 before it runs.
- The code lives in the part of the link after the `#`, so it is never sent to the website.
- Nothing is installed system-wide. At the end you can clean up the small helper program it used. Your transferred files are never touched.

## Run it directly

```
bash <(curl -fsSL https://justinoros.github.io/crocdrop/crocdrop.sh) receive YOUR-CODE
bash <(curl -fsSL https://justinoros.github.io/crocdrop/crocdrop.sh) send YOUR-CODE /path/to/folder
```

You can also add a folder as the last argument of receive to choose where files are saved.

## Advanced

Set `CROCDROP_FLAGS` to pass extra croc options on both sides, for example `--no-compress` or `--relay your-server:9009`. Set `CROCDROP_SEND_FLAGS` for options that only apply when sending, such as `--transport relay`.

Mac and Linux:

```
CROCDROP_FLAGS="--no-compress" bash <(curl -fsSL https://justinoros.github.io/crocdrop/crocdrop.sh) receive YOUR-CODE
```

Windows PowerShell:

```
$env:CROCDROP_FLAGS = "--no-compress"
```

Then paste the normal command in the same window.

## Files

- `index.html` the web page
- `crocdrop.sh` launcher for Mac and Linux
- `crocdrop.ps1` launcher for Windows

## License

croc is MIT licensed, by Zack Scholl.

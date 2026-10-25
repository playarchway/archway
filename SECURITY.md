# Security

Please report security issues privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Don't open a public issue for them.

Relevant are, for example, ways for a downloaded runtime, Steam, or a game to reach outside Archway's data directory, problems with how Archway verifies what it downloads, or anything that exposes Steam sign-in data.

Archway runs Windows programs through Wine without a sandbox; a Windows program can read and write the files of the Mac user who runs it. That is how Wine works and not a vulnerability in Archway, but suggestions to narrow it are welcome.

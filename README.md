<h2></h2><div>
<a href="../.."><img align="right" height="98" src="assets/logo.png" alt="logo"></a>
<h1>machogen</h1>
<p>Monterey post installation script</p>
</div><h2></h2>

## Usages

### Add the needed passwords in the keychain

```sh
security add-generic-password -s "account" -a "$USER" -w "account_password"
security add-generic-password -s "appleid" -a "$USER" -w "appleid_username"
security add-generic-password -s "secrets" -a "$USER" -w "appleid_password"
```

### Get and run the post installation script

Upon first launch, you will probably have to perform some manual operations.  
Those are required to set proper permissions, just follow the alert windows.

```shell
/bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/sharpordie/machogen/master/src/machogen.sh)"
```

Attention, the total execution of the script may take **more than 3 hours**.

## `Support`

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://uploads-ssl.webflow.com/5c14e387dab576fe667689cf/61e11ddcc39341db4958c5cc_Supportbutton.png">
  <source media="(prefers-color-scheme: light)" srcset="https://uploads-ssl.webflow.com/5c14e387dab576fe667689cf/61e11e22d8ff4a5b4a1b3346_Supportbutton-1.png">
  <a href="https://ko-fi.com/supportkofi" target="_blank">
    <img width="300px" alt="" src="https://uploads-ssl.webflow.com/5c14e387dab576fe667689cf/61e11e22d8ff4a5b4a1b3346_Supportbutton-1.png">
  </a>
</picture>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://uploads-ssl.webflow.com/5c14e387dab576fe667689cf/61e11e22d8ff4a5b4a1b3346_Supportbutton-1.png">
  <source media="(prefers-color-scheme: light)" srcset="https://uploads-ssl.webflow.com/5c14e387dab576fe667689cf/61e11ddcc39341db4958c5cc_Supportbutton.png">
  <a href="https://ko-fi.com/supportkofi" target="_blank">
    <img width="300px" alt="" src="https://uploads-ssl.webflow.com/5c14e387dab576fe667689cf/61e11ddcc39341db4958c5cc_Supportbutton.png">
  </a>
</picture>

## Gallery

<a href="assets/img1.png"><img src="assets/img1.png" width="49.5%"/></a><a><img src="assets/none.png" width="1%"/></a><a href="assets/img2.png"><img src="assets/img2.png" width="49.5%"/></a>

## License

This project is offered under the [MIT](LICENSE.md) license.

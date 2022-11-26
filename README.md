<hr><div>
<a href="https://ko-fi.com/sharpordie" target="_blank"><img align="right" height="91px" alt="Donate" src="https://user-images.githubusercontent.com/72373746/204102533-cc38d6db-cdd6-471b-ad08-1b6d5f7ea96f.png"></a>
<h1>machogen</h1>
<p>Configuration script for macOS</p>
</div><hr>

## `Samples`

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

## `Gallery`

<a href="assets/img1.png"><img src="assets/img1.png" width="49.5%"/></a><a><img src="assets/none.png" width="1%"/></a><a href="assets/img2.png"><img src="assets/img2.png" width="49.5%"/></a>

# Deploying [listmonk](https://listmonk.app) on [Fly.io](https://fly.io)

## Useful Resources

- [Fly docs](https://fly.io/docs/)
- [Fly community](https://community.fly.io)
- [Listmonk docs](https://listmonk.app/docs/)
- [Listmonk github issues](https://github.com/knadh/listmonk/issues)

## Steps and suggestions

_Note: Any instance of angled brackets (e.g., `<app-name>`) denotes something to be replaced with an actual value or name, minus the angled brackets._

### 1. Clone this repository to your computer

This repo contains:

- `fly.toml`, which Fly uses to configure app deployment
- `Dockerfile`, which Fly uses to build the app
- `static/`, which is a copy of [listmonk's static directory](https://github.com/knadh/listmonk/tree/master/static) for purposes of customization

Note: Fly uses Dockerfiles to deploy apps, but _it does not deploy Docker containers_. Instead, it create a Firecracker VM based on the Dockerfile.

### 2. Set up the CLI `flyctl`

Follow [these instructions](https://fly.io/docs/hands-on/install-flyctl/) to install the CLI `flyctl`.

If you don't already have a Fly account, run `flyctl auth signup` and sign up.

Log in with `flyctl auth login`.

### 3. Set up app deployment

`cd` to the directory where you cloned this repo. This will be the working directory that `flyctl` associates with this particular app.

Open `fly.toml` and look at `[build]` section, which provides keys and values for the application build:

```
[build]
  dockerfile = "./Dockerfile"
  ADMIN_USERNAME=""
  ADMIN_PASSWORD=""
  POSTGRES_HOST=""
  POSTGRES_PORT=5432
  POSTGRES_USER="listmonk"
  POSTGRES_PASSWORD=""
  POSTGRES_DATABASE=""
```

Copy this section and save it somewhere, since Fly's `launch` command might remove it, and you'll need to add it back and edit it.

Enter `flyctl launch` to go create a new app and an attached Postgres database app.

When `flyctl launch` asks you if you'd like to copy the configuration of the existing `fly.toml` file, type `y`.

You can have it automatically generate an app name, or choose one yourself.

Choose the default organization (personal)—you can always change this later.

Select a region to deploy the app in. Fly will pre-select a region near your IP address. **Take note of the three-character code representing your region**. You'll need it later.

When it asks you if you want to set up a Postgres database, type `y`.

Choose the "Development" level configuration (lowest, free tier).

Once your postgres cluster is created, copy the information `flyctl` displays: `Username`, `Password`, `Hostname`, `Proxy Port`, and `PG Port`. These are all default values or based on your app name, but `Password` is unique, so be sure you save it.

Also take note of the name of your Postgres app in the line:

```
Postgres cluster <app-name-db> is now attached to <app-name>
```

When `flyctl launch` asks you if you want to deploy now, type `n`, in order to do some preliminary setup.

### 4. Create a `listmonk` Postgres user (role)

It's best not to give an app superuser database credentials like the `postgres` user and its password that you copied. So create a new user in your postgres app:

`flyctl postgres connect -a <app-name-db>`

In the postgres command line, type `\l` to list databases in the cluster. You'll see a database entry that closely matches your app's name. This is the database the listmonk app will use. **Take note of the database name**, since it may be slightly different from your app name.

Create and save a secure and unique password for the new `listmonk` user.

Type `CREATE USER listmonk WITH ENCRYPTED PASSWORD '<new password>';`, placing your new password between the single quotes `'`. Be sure to include the `;` at the end, which terminates the command.

Type `GRANT ALL PRIVILEGES ON DATABASE <database_name> TO listmonk;`, substituting `<database_name>` with the name of your database.

Type `\q` to exit the postgres command line.

### 5. Create persistent disk storage on Fly

You'll need the three-character `<region code>` from when you used `fly launch`

Use `flyctl vol create listmonk_data --region <region code> --size 1` to create a persistent storage volume called `listmonk_data` in the same region as your app.

### 6. Enter keys and values to pass to listmonk at build time

Edit `fly.toml` and check if the `[build]` section you copied is still there. It likely isn't. Re-add it from your copy (or copy this repo). I don't think placement matters, but I put it just above `[env]`.

Between the double quotes `"` for each key, enter the following info that you'll be passing in to your listmonk app build:

- `ADMIN_USERNAME`: create a user name for accessing listmonk's admin page with
- `ADMIN_PASSWORD`: create a unique password for that user name
- `POSTGRES_HOST`: the url `fly launch` gave you along with the `postgres` password (it's probably `<app-name-db>.internal`)
- `POSTGRES_PASSWORD`: the password you _created_ when you made the `listmonk` user in the Postgres command line—_not_ the master `postgres` password that you saved earlier.
- `POSTGRES_DATABASE`: the name of the database you granted access to for user `listmonk`.

Check that the following section still exists in `fly.toml`, and if not, add it.

```
[mounts]
  destination = "/data"
  source = "listmonk_data"
```

### 7. Deploy!

Use `flyctl deploy` to deploy the app.

Once the deployment is finished, you can find your app at `<app-name>.fly.dev`, and log in with the user name and password you chose.

If you want to use a custom domain for your listmonk install, follow [these instructions](https://fly.io/docs/app-guides/custom-domains-with-fly/).

#### Notes on the Dockerfile:

At build time, Fly will pull the build values and plug them into the Dockerfile's `ENV` variables, which will be used to configure listmonk.

The Dockerfile's `COPY static/ /tmp/static/` line copies the `static/` folder into temporary storage on the app.

Then the commands in `CMD`, which run once the persistent storage volume is mounted, copy the `static/` folder to persistent storage, and install/upgrade/run listmonk.

### 8. Edit listmonk's system templates

For reference: listmonk's [docs about its system templates](https://listmonk.app/docs/templating/#system-templates).

To edit the system templates, simply make your edits in the `static/` directory on your computer.

To deploy the changes, use `fly deploy` (making sure you're in the root directory of the for the Fly app).

### Notes

listmonk has an option `ssl_mode` that can be enabled, in order to encrypt traffic between the listmonk app and its database, in case of snooping by unauthorized processes or users on the server.

On Fly, this is unnecessary because:

- Fly creates a private and encrypted network using Wireguard between the the app and its database (via `<app-name-db>.internal`)
- Accessing the Postgres database from the command line uses this same encrypted connection.

(See [this comment](https://community.fly.io/t/seeking-advice-about-securing-postgres-on-fly/7861?u=paulrudy) for reference).

### Optionally add a replica of the Postgres volume

In case of database failure, it's good to have a backup. Adding a replica is simple. First, though, read about encrypting the Postgres volume below. If you choose to do that, creating a replica is already part of that process.

If you don't want to encrypt, just create a replica like this:

`flyctl volumes list <app-name-db>` and get the size of the volume.

`flyctl volumes create pg_data -a <app-name-db> --size <same size as original volume> --region <region code> --no-encryption` and choose a different region for a volume.

Create other encrypted volumes if desired with the same command.

Then scale out your app to include these volumes as replicas. `flyctl scale count <# of volumes including replicas> -a <app-name-db>`

Use `flyctl status -a <app-name-db>` to check that the new volume is running with no errors. May take a minute or two.

### Optionally encrypt the Postgres volume

`flyctl launch` creates encrypted app volumes by default, except for Postgres app volumes.

If you want to encrypt the Postgres app volume, there may be an easier way but this how I did it:

`flyctl volumes list <app-name-db>` and get the size of the volume.

`flyctl volumes create pg_data -a <app-name-db> --size <same size as original volume> --region <region code>` and choose a different region for a volume.

Create other encrypted volumes if desired with the same command.

Then scale out your app to include these volumes as replicas. `flyctl scale count <# of volumes including replicas> -a <app-name-db>`

Use `flyctl status -a <app-name-db>` to check that the new volume is running with no errors. May take a minute or two.

> #### Changing the primary region of the app
>
> (instructions taken from [this post](https://community.fly.io/t/what-is-the-correct-process-to-change-the-postgres-leader-region/4831/2))
>
> Create a new empty directory on your computer for the files of the Postgres app and `cd` into it.
>
> `flyctl config save --app <app-name-db>` to save the Postgres app's `fly.toml` configuration file.
>
> In `fly.toml`, edit `PRIMARY_REGION` to match new region code.
>
> Get the major version of your Postgres with `flyctl image show`. (If Tag indicates `14.2`, major version is `14`).
>
> `flyctl deploy . --image flyio/postgres:<major-version> --strategy=immediate`
>
> For Postgres 13/14: `flyctl ssh console --app <app-name-db>` then in the ssh shell, `pg-failover`, then after success, `exit`. (For other versions of Postgres, see [the original post](https://community.fly.io/t/what-is-the-correct-process-to-change-the-postgres-leader-region/4831/2))
>
> Check `flyctl status` until new region shows as leader and not replica.
>
> _(End of [Changing the primary region of the app](https://github.com/paulrudy/listmonk-on-fly/#changing-the-primary-region-of-the-app))_

Once the volume in _original region_ shows as a replica, get its `<volume id>` with `flyctl volumes list` and delete it with `flyctl volumes delete <volume id>`.

Create an encrypted replica in the original region: `flyctl volumes create pg_data -a <app-name-db> --size <same size as original volume> --region <region code>` and choose the original region.

Repeat the steps above for [Changing the primary region of the app](https://github.com/paulrudy/listmonk-on-fly/#changing-the-primary-region-of-the-app), but this time to move it from the new back to the original region.

Use `flyctl status` to confirm original region is the leader.

If you want to keep the replica(s) you created as backups in case of corruption or failure of the database, then you're done. If you want to go back to only one volume, then double-check that you know which volume is the replica to delete with `flyctl status`, then get the replica's `<volume id>` with `flyctl volumes list` and delete it with `flyctl volumes delete <volume id>`.

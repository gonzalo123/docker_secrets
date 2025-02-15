from get_docker_secret import get_docker_secret


def get_secret(key, default=None):
    return get_docker_secret(
        name=f"{key}.tmp",
        default=get_docker_secret(name=key, default=default)
    )

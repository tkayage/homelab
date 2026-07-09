ssh localhost "sudo bash -c '
    CONF=\"test_file\"
    echo \"#listen_addresses = localhost\" > \$CONF
    sed -i \"s/#listen_addresses = .*/listen_addresses = \\'*\\' /\" \$CONF
    cat \$CONF
'"
